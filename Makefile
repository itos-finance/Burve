# Pinned Berachain block for reproducible fork tests
FORK_BLOCK := 17257479
FORK_URL := $(shell grep '^FORK_URL=' .env 2>/dev/null | cut -d'=' -f2 | tr -d '"')
ANVIL_URL := http://127.0.0.1:8545
ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

.PHONY: anvil-fork test-fork test-fork-looper test-lender test-looper test-all-fork test \
	liq-deploy liq-setup liq-crash liq-execute liq-e2e

# ============================================================
#  Anvil Fork
# ============================================================

anvil-fork:
	anvil --fork-url $(FORK_URL) --fork-block-number $(FORK_BLOCK) --chain-id 80094

# ============================================================
#  Tests
# ============================================================

test-fork:
	forge test --fork-url $(FORK_URL) --fork-block-number $(FORK_BLOCK) -vvv \
		--match-path 'test/integrations/lender/BurveLender.fork.t.sol'

test-fork-looper:
	forge test --fork-url $(FORK_URL) --fork-block-number $(FORK_BLOCK) -vvv \
		--match-path 'test/integrations/looper/BurveLooper.fork.t.sol'

test-lender:
	forge test --match-path 'test/integrations/lender/BurveLender.t.sol' -vvv

test-looper:
	forge test --match-path 'test/integrations/looper/BurveLooper.t.sol' -vvv

test-all-fork:
	forge test --fork-url $(FORK_URL) --fork-block-number $(FORK_BLOCK) -vvv \
		--match-path 'test/integrations/'

test:
	forge test

# ============================================================
#  Liquidator Scenario Scripts (run against Anvil fork)
#  Start anvil-fork first in another terminal, then:
#    make liq-deploy    → deploys BurveLender + mock oracles
#    make liq-setup     → creates positions (needs BURVE_LENDER=0x...)
#    make liq-crash     → crashes oracle prices
#    make liq-execute   → liquidates unhealthy positions
#    make liq-e2e       → runs everything in one script
# ============================================================

liq-deploy:
	DEPLOYER_PRIVATE_KEY=$(ANVIL_KEY) \
	forge script script/liquidator/DeployLenderAnvil.s.sol \
		--rpc-url $(ANVIL_URL) --broadcast -vvv

liq-setup:
	@test -n "$(BURVE_LENDER)" || (echo "Error: set BURVE_LENDER=0x..." && exit 1)
	DEPLOYER_PRIVATE_KEY=$(ANVIL_KEY) \
	BURVE_LENDER=$(BURVE_LENDER) \
	forge script script/liquidator/SetupPositions.s.sol \
		--rpc-url $(ANVIL_URL) -vvv

liq-crash:
	@test -n "$(BURVE_LENDER)" || (echo "Error: set BURVE_LENDER=0x..." && exit 1)
	DEPLOYER_PRIVATE_KEY=$(ANVIL_KEY) \
	BURVE_LENDER=$(BURVE_LENDER) \
	forge script script/liquidator/CrashOracle.s.sol \
		--rpc-url $(ANVIL_URL) --broadcast -vvv

liq-execute:
	@test -n "$(BURVE_LENDER)" || (echo "Error: set BURVE_LENDER=0x..." && exit 1)
	DEPLOYER_PRIVATE_KEY=$(ANVIL_KEY) \
	BURVE_LENDER=$(BURVE_LENDER) \
	forge script script/liquidator/Liquidate.s.sol \
		--rpc-url $(ANVIL_URL) --broadcast -vvv

liq-e2e:
	DEPLOYER_PRIVATE_KEY=$(ANVIL_KEY) \
	forge script script/liquidator/E2EScenario.s.sol \
		--rpc-url $(ANVIL_URL) -vvv
