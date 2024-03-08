# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# deps
update:; forge update

# Build & test
build  :; forge build --sizes
test   :; forge test -vvv

deploy-ledger :; forge script ${contract} --rpc-url ${chain} $(if ${dry},--sender 0x25F2226B597E8F9514B3F68F00f494cF4f286491 -vvvv,--broadcast --ledger --mnemonics foo --mnemonic-indexes ${MNEMONIC_INDEX} --sender ${LEDGER_SENDER} --verify -vvvv)

# scripts
polygonv2 :; make deploy-ledger contract=scripts/Deploy.s.sol:PolygonV2 chain=polygon
polygonv3 :; make deploy-ledger contract=scripts/Deploy.s.sol:PolygonV3 chain=polygon

avalanchev2 :; make deploy-ledger contract=scripts/Deploy.s.sol:AvalancheV2 chain=avalanche
avalanchev3 :; make deploy-ledger contract=scripts/Deploy.s.sol:AvalancheV3 chain=avalanche

arbitrumv3 :; make deploy-ledger contract=scripts/Deploy.s.sol:ArbitrumV3 chain=arbitrum

optimismv3 :; make deploy-ledger contract=scripts/Deploy.s.sol:OptimismV3 chain=optimism

ethereumv2 :; make deploy-ledger contract=scripts/Deploy.s.sol:EthereumV2 chain=mainnet
ethereumv3 :; make deploy-ledger contract=scripts/Deploy.s.sol:EthereumV3 chain=mainnet

basev3 :; make deploy-ledger contract=scripts/Deploy.s.sol:BaseV3 chain=base
bnbv3 :;  make deploy-ledger contract=scripts/Deploy.s.sol:BNBV3 chain=bnb
