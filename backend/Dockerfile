# Build from the MONOREPO ROOT so path dependencies in ../packages resolve:
#   docker build -f backend/Dockerfile -t eazyclinic-backend .
FROM dart:stable AS build

WORKDIR /workspace
COPY packages/api_contracts packages/api_contracts
COPY packages/common_models packages/common_models
COPY packages/country_config packages/country_config
COPY packages/utilities packages/utilities
COPY packages/validation packages/validation
COPY backend backend

WORKDIR /workspace/backend
RUN dart pub get
RUN dart compile exe bin/server.dart -o bin/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /workspace/backend/bin/server /app/bin/

# Configuration comes from environment variables (see environments/*/backend.env.example).
EXPOSE 8080
CMD ["/app/bin/server"]
