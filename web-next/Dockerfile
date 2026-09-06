FROM node:24-alpine AS builder

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .

ARG NEXT_PUBLIC_RELEASE_SHA=dev
ARG NEXT_PUBLIC_GIT_SHA=dev
ARG NEXT_PUBLIC_BUILD_TIME=unknown
ARG API_PROXY_TARGET=https://shengbeijiang.com
ENV OUTPUT_STANDALONE=true
ENV NEXT_PUBLIC_RELEASE_SHA=${NEXT_PUBLIC_RELEASE_SHA}
ENV NEXT_PUBLIC_GIT_SHA=${NEXT_PUBLIC_GIT_SHA}
ENV NEXT_PUBLIC_BUILD_TIME=${NEXT_PUBLIC_BUILD_TIME}
ENV API_PROXY_TARGET=${API_PROXY_TARGET}
RUN npm run build

FROM node:24-alpine

ENV NODE_ENV=production
ENV HOSTNAME=0.0.0.0
ENV PORT=3000
WORKDIR /app

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

EXPOSE 3000
CMD ["node", "server.js"]
