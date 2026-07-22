set shell := ["bash", "-cu"]
set windows-shell := ["powershell.exe", "-NoLogo", "-NoProfile", "-Command"]

# Run DynamoDB Local via Docker
run-dynamodb:
	docker run -d --name dynamodb-local -p 8000:8000 amazon/dynamodb-local:latest -jar DynamoDBLocal.jar -sharedDb

# Seed test data into DynamoDB Local
seed-dynamodb:
	# Create test tables
	aws dynamodb create-table \
		--endpoint-url http://localhost:8000 \
		--table-name users \
		--attribute-definitions AttributeName=id,AttributeType=S \
		--key-schema AttributeName=id,KeyType=HASH \
		--billing-mode PAY_PER_REQUEST
	aws dynamodb create-table \
		--endpoint-url http://localhost:8000 \
		--table-name orders \
		--attribute-definitions AttributeName=id,AttributeType=S AttributeName=user_id,AttributeType=S \
		--key-schema AttributeName=id,KeyType=HASH AttributeName=user_id,KeyType=RANGE \
		--global-secondary-indexes IndexName=user_id-index,KeySchema=["{AttributeName=user_id,KeyType=HASH}"],Projection={ProjectionType=ALL} \
		--billing-mode PAY_PER_REQUEST
	# Seed data
	aws dynamodb put-item --endpoint-url http://localhost:8000 --table-name users --item '{"id": {"S": "user1"}, "name": {"S": "Alice"}, "email": {"S": "alice@example.com"}, "age": {"N": "30"}}'
	aws dynamodb put-item --endpoint-url http://localhost:8000 --table-name users --item '{"id": {"S": "user2"}, "name": {"S": "Bob"}, "email": {"S": "bob@example.com"}, "age": {"N": "25"}}'
	aws dynamodb put-item --endpoint-url http://localhost:8000 --table-name orders --item '{"id": {"S": "order1"}, "user_id": {"S": "user1"}, "total": {"N": "99.99"}, "status": {"S": "shipped"}}'

# Build the plugin binary in debug mode
build:
	cargo build

# Build for release
release:
	cargo build --release

# Run unit tests
test:
	cargo test

# Run tests with output
test-verbose:
	cargo test -- --nocapture

# Launch the local REPL
repl:
	cargo run --bin test_plugin

# Run clippy
lint:
	cargo clippy --all-targets -- -D warnings

# Format code
fmt:
	cargo fmt --all

# Build + copy binary and manifest into Tabularis plugin folder
[windows]
dev-install: build
	#!pwsh
	$dest = Join-Path $env:APPDATA "debba\tabularis\data\plugins\dynamodb"
	New-Item -ItemType Directory -Force -Path $dest | Out-Null
	Copy-Item "target\debug\tabularis-dynamodb-plugin.exe" $dest
	Copy-Item "manifest.json" $dest
	Write-Host "Installed to $dest"
	Write-Host "Restart Tabularis (or toggle the plugin in Settings) to pick up changes."

[unix]
dev-install: build
	mkdir -p ~/.local/share/tabularis/plugins/dynamodb
	cp target/debug/tabularis-dynamodb-plugin ~/.local/share/tabularis/plugins/dynamodb/
	cp manifest.json ~/.local/share/tabularis/plugins/dynamodb/
	@echo "Installed to ~/.local/share/tabularis/plugins/dynamodb"
	@echo "Restart Tabularis to pick up changes."

[windows]
uninstall:
	$dest = Join-Path $env:APPDATA "debba\tabularis\data\plugins\dynamodb"
	if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }

[unix]
uninstall:
	rm -rf ~/.local/share/tabularis/plugins/dynamodb
