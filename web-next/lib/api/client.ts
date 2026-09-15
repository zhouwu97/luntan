import { apiRoot } from "../config";

export class ApiError extends Error {
  status: number;
  code?: string;

  constructor(message: string, status: number, code?: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
  }
}

let accessToken: string | null = null;
let sessionVersion = 0;
let refreshInFlight: { version: number; promise: Promise<boolean> } | null = null;

function requestUrl(path: string): string {
  if (/^https?:\/\//i.test(path)) return path;
  return `${apiRoot}${path.startsWith("/") ? path : `/${path}`}`;
}

async function readPayload(response: Response): Promise<Record<string, unknown>> {
  const text = await response.text();
  if (!text.trim()) return {};
  try {
    const payload = JSON.parse(text) as unknown;
    return payload && typeof payload === "object" ? (payload as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

function errorFields(payload: Record<string, unknown>): { message: string; code?: string } {
  const nested = payload.error && typeof payload.error === "object"
    ? payload.error as Record<string, unknown>
    : {};
  const message = typeof payload.message === "string"
    ? payload.message
    : typeof nested.message === "string"
      ? nested.message
      : "请求失败";
  const code = typeof payload.code === "string"
    ? payload.code
    : typeof nested.code === "string"
      ? nested.code
      : undefined;
  return { message, code };
}

async function fetchWithTimeout(input: RequestInfo | URL, init: RequestInit = {}, timeoutMs = 8_000): Promise<Response> {
  const controller = new AbortController();
  const timer = globalThis.setTimeout(() => controller.abort(), timeoutMs);
  const externalSignal = init.signal;
  const abortFromExternal = () => controller.abort();
  if (externalSignal) {
    if (externalSignal.aborted) controller.abort();
    else externalSignal.addEventListener("abort", abortFromExternal, { once: true });
  }
  try {
    return await fetch(input, { ...init, signal: controller.signal });
  } finally {
    globalThis.clearTimeout(timer);
    externalSignal?.removeEventListener("abort", abortFromExternal);
  }
}

async function send(path: string, init: RequestInit = {}, token = accessToken): Promise<Response> {
  const headers = new Headers(init.headers);
  headers.set("Accept", "application/json");
  if (init.body && !headers.has("Content-Type")) headers.set("Content-Type", "application/json");
  if (token) headers.set("Authorization", `Bearer ${token}`);
  return fetchWithTimeout(requestUrl(path), {
    ...init,
    headers,
    credentials: "include",
    cache: "no-store",
  });
}

async function refreshSessionInternal(version: number): Promise<boolean> {
  const response = await fetchWithTimeout(requestUrl("/auth/refresh"), {
    method: "POST",
    headers: { Accept: "application/json", "Content-Type": "application/json" },
    body: JSON.stringify({}),
    credentials: "include",
    cache: "no-store",
  });
  if (!response.ok) {
    if (sessionVersion === version) accessToken = null;
    return false;
  }
  const payload = await readPayload(response);
  const nextToken = typeof payload.access_token === "string" ? payload.access_token : "";
  if (!nextToken) {
    if (sessionVersion === version) accessToken = null;
    return false;
  }
  if (sessionVersion !== version) return false;
  accessToken = nextToken;
  return true;
}

export async function refreshSession(): Promise<boolean> {
  const version = sessionVersion;
  if (refreshInFlight?.version === version) return refreshInFlight.promise;
  const promise = refreshSessionInternal(version).finally(() => {
    if (refreshInFlight?.promise === promise) refreshInFlight = null;
  });
  refreshInFlight = { version, promise };
  return promise;
}

export function setAccessToken(token: string | null): void {
  sessionVersion += 1;
  accessToken = token;
}

export function clearAccessToken(): void {
  sessionVersion += 1;
  accessToken = null;
}

export function getSessionVersion(): number {
  return sessionVersion;
}

export async function apiFetch(path: string, init: RequestInit = {}): Promise<Response> {
  const requestVersion = sessionVersion;
  const requestToken = accessToken;
  let response = await send(path, init, requestToken);
  const isAuthRoute = path.startsWith("/auth/");
  if (
    response.status === 401 &&
    !isAuthRoute &&
    sessionVersion === requestVersion &&
    (await refreshSession()) &&
    sessionVersion === requestVersion
  ) {
    // 会话切换或退出后，旧请求不得带着当前账号令牌重放。
    response = await send(path, init, accessToken);
  }
  if (!response.ok) {
    const payload = await readPayload(response);
    const { message, code } = errorFields(payload);
    throw new ApiError(message, response.status, code);
  }
  return response;
}

export async function apiJson<T>(path: string, init: RequestInit = {}): Promise<T> {
  const response = await apiFetch(path, init);
  const payload = await readPayload(response);
  return payload as T;
}

export async function apiPost<T>(path: string, body?: unknown, headers?: HeadersInit): Promise<T> {
  return apiJson<T>(path, {
    method: "POST",
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}
