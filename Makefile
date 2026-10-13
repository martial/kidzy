# Kidzy: one Go binary (server + embedded admin) and an iPhone app.
.PHONY: build admin server test test-go test-admin test-ios run xcodeproj

build: admin server          ## admin bundle then the Go binary with it embedded

admin:
	npm --prefix admin run build

server:
	cd server && go build -o bin/kidzy ./cmd/kidzy

test: test-go test-admin test-ios

test-go:
	cd server && go test -race ./... && go vet ./...

test-admin:
	npm --prefix admin test --silent

test-ios:
	swift test --package-path ios/Kidzy

run: server                  ## run in the foreground with ~/.config/kidzy/kidzy.env
	./server/bin/kidzy

xcodeproj:                   ## regenerate ios/Kidzy/Kidzy.xcodeproj from project.yml
	cd ios/Kidzy && xcodegen generate
