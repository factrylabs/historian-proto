major = 2
minor = 1
patch = 0

PROTO_DIR= .
PROTO_FILES = $(PROTO_DIR)/*/*.proto

.DEFAULT_GOAL := help
.PHONY: help version version_major_bump version_minor_bump version_patch_bump gen_proto

help: ## These help instructions
	@grep -E '^[a-z0-9A-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

version: ## Prints the current version
ifdef prerelease
	@echo v$(major).$(minor).$(patch)$(prerelease)-$(COMMIT)
else
	@echo v$(major).$(minor).$(patch)
endif

version_major_bump: ## Bumps the major version and resets the minor and patch versions
	@sed 's/^patch = $(patch)$$/patch = 0/' Makefile > tmp && mv tmp Makefile
	@sed 's/^minor = $(minor)$$/minor = 0/' Makefile > tmp && mv tmp Makefile
	@sed 's/^major = $(major)$$/major = $(shell expr $(major) + 1)/' Makefile > tmp && mv tmp Makefile

version_minor_bump: ## Bumps the minor version and resets the patch version
	@sed 's/^patch = $(patch)$$/patch = 0/' Makefile > tmp && mv tmp Makefile
	@sed 's/^minor = $(minor)$$/minor = $(shell expr $(minor) + 1)/' Makefile > tmp && mv tmp Makefile

version_patch_bump: ## Bumps the patch version
	@sed 's/^patch = $(patch)$$/patch = $(shell expr $(patch) + 1)/' Makefile > tmp && mv tmp Makefile

gen_proto: ## Generates the go files from the .proto files
	protoc --go_out=. --go_opt=paths=source_relative --go-grpc_out=. --go-grpc_opt=paths=source_relative $(PROTO_FILES)
