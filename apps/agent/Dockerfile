FROM node:22-alpine AS build
WORKDIR /app
RUN corepack enable
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml turbo.json tsconfig.base.json ./
COPY apps/agent/package.json apps/agent/package.json
COPY packages/contracts/package.json packages/contracts/package.json
COPY packages/core/package.json packages/core/package.json
RUN pnpm install --frozen-lockfile
COPY apps/agent apps/agent
COPY packages packages
RUN pnpm --filter @joi/contracts build && pnpm --filter @joi/core build && pnpm --filter @joi/agent build

FROM node:22-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production PORT=8787
RUN corepack enable
COPY --from=build /app /app
EXPOSE 8787
CMD ["pnpm", "--filter", "@joi/agent", "start"]
