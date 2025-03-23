.PHONY: build run pause stop clean update

all: build

# outputs
BUILD_DIR := build
QEMU_IMAGE := $(BUILD_DIR)/qemu-image
VM_QCOW2 := $(BUILD_DIR)/nixos.qcow2

# sources
FLAKE_FILE := flake.nix
FLAKE_LOCK := flake.lock
NIX_FILES := $(shell find . -name "*.nix" -type f)
SH_FILES := $(shell find . -name "*.sh" -type f)
RUST_FILES := $(shell find . -name "*.rs" -type f)

# docker config
IMAGE_NAME := qemu-image:latest
CONTAINER_NAME := qemu-container

$(QEMU_IMAGE): $(FLAKE_FILE) $(FLAKE_LOCK) $(NIX_FILES) $(SH_FILES) $(RUST_FILES)
	nix build .#qemuImage
	mkdir -p $(BUILD_DIR)
	cp -f -L result $(QEMU_IMAGE)

$(VM_QCOW2): $(FLAKE_FILE) $(FLAKE_LOCK) $(NIX_FILES) $(SH_FILES) $(RUST_FILES)
	nix build .#qcow2
	cp -f -L result/nixos.qcow2 $(VM_QCOW2)

build: $(QEMU_IMAGE) $(VM_QCOW2)
	@echo "Build up to date!"

run: stop build
	docker load < $(QEMU_IMAGE)
	docker run --privileged --rm -d \
		-p 2222:2222 \
		-p 25560:25560 \
		-v $(PWD)/$(VM_QCOW2):/app.qcow2 \
		--name $(CONTAINER_NAME) \
		$(IMAGE_NAME)

pause:
	-docker exec -it $(CONTAINER_NAME) icetainer-tools

stop: pause
	@docker stop $(CONTAINER_NAME) 2>/dev/null || true
	@docker rm $(CONTAINER_NAME) 2>/dev/null || true

logs:
	docker logs -f $(CONTAINER_NAME) 2>/dev/null

update:
	nix flake update

clean: stop
	rm -rf result
	rm -rf $(BUILD_DIR)
	-docker rmi $(IMAGE_NAME)
