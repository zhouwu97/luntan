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
let refreshInFlight: Promise<boolean> | null = null;

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

async function send(path: string, init: RequestInit = {}): Promise<Response> {
  const headers = new Headers(init.headers);
  headers.set("Accept", "application/json");
  if (init.body && !headers.has("Content-Type")) headers.set("Content-Type", "application/json");
  if (accessToken) headers.set("Authorization", `Bearer ${accessToken}`);
  return fetch(requestUrl(path), {
    ...init,
    headers,
    credentials: "include",
    cache: "no-store",
  });
}

async function refreshSessionInternal(): Promise<boolean> {
  const response = await fetch(requestUrl("/auth/refresh"), {
    method: "POST",
    headers: { Accept: "application/json", "Content-Type": "application/json" },
    body: JSON.stringify({}),
    credentials: "include",
    cache: "no-store",
  });
  if (!response.ok) {
    accessToken = null;
    return false;
  }
  const payload = await readPayload(response);
  const nextToken = typeof payload.access_token === "string" ? payload.access_token : "";
  if (!nextToken) return false;
  accessToken = nextToken;
  return true;
}

export async function refreshSession(): Promise<boolean> {
  if (!refreshInFlight) {
    refreshInFlight = refreshSessionInternal().finally(() => {
      refreshInFlight = null;
    });
  }
  return refreshInFlight;
}

export function setAccessToken(token: string | null): void {
  accessToken = token;
}

export function clearAccessToken(): void {
  accessToken = null;
}

export async function apiFetch(path: string, init: RequestInit = {}): Promise<Response> {
  let response = await send(path, init);
  const isAuthRoute = path.startsWith("/auth/");
  if (response.status === 401 && !isAuthRoute && (await refreshSession())) {
    response = await send(path, init);
  }
  if (!response.ok) {
    const payload = await readPayload(response);
    const message = typeof payload.message === "string" ? payload.message : "请求失败";
    const code = typeof payload.code === "string" ? payload.code : undefined;
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
