# AutoTopUpTrap — README

**Purpose:**
Monitor the **6ixty** ERC-20 token balance of your SAFE and automatically top it up from a pre-approved FUNDING wallet when the SAFE falls below **500,000 tokens** or drops by **50% vs previous sample**. The responder pulls tokens using `transferFrom()` — FUNDING must first approve the responder.

---

## 📌 System Variables (Static for PoC)

| Parameter                         | Value                                        |
| --------------------------------- | -------------------------------------------- |
| Token (6ixty)                     | `0xab16D6FF7295Dfc304c3C816c7e6d62926d2f7A4` |
| SAFE (Monitored)                  | `0xD78a2D9D050bd1C8bef581Aa6Da507193708776A` |
| FUNDING                           | `0x69375A9b81633Ce35e758a5972cd037E3Aca1FAa` |
| Operator (Whitelisted by Drosera) | `0x0c5832C5fa862E1dBc765408f7987AAd4F7E7647` |
| Threshold                         | `500,000 tokens` (scaled by decimals)        |
| Restore Target                    | `80% of last known balance`                  |

---

## ✅ Prerequisites

```
forge       → Foundry CLI
drosera-cli → Drosera Trap Manager
RPC         → testnet RPC (e.g Hoodi)
EXPORT VARIABLES:
export RPC="https://0xrpc.io/hoodi"
export OPERATOR_PK="0x...."
export FUNDING_PK="0x...."  (never expose publicly)
```

---

## 🏗️ Build

```
forge build --via-ir
```

---

## 🚀 Deployment Order

### 1. Deploy the Responder (FIRST!)

```
forge create src/TopUpResponder.sol:TopUpResponder \
  --rpc-url $RPC \
  --private-key $OPERATOR_PK
```

→ Save the **RESPONDER ADDRESS**

### 2. FUNDING Wallet Approves Responder

```
AMOUNT=$(cast to-wei 2000000 eth)  # or use exact decimals
cast send 0xab16D6FF7295Dfc304c3C816c7e6d62926d2f7A4 \
"approve(address,uint256)" $RESPONDER_ADDRESS $AMOUNT \
--rpc-url $RPC --private-key $FUNDING_PK
```

### 3. Deploy the Trap

```
forge create src/AutoTopUpTrap.sol:Trap \
  --rpc-url $RPC \
  --private-key $OPERATOR_PK
```

### 4. Update `drosera.toml`

```
[traps.autotopup]
path = "out/AutoTopUpTrap.sol/Trap.json"
response_contract = "0xRESPONDER_ADDRESS"
response_function = "respondAndTopUp(address,address,uint256)"
whitelist = ["0x0c5832C5fa862E1dBc765408f7987AAd4F7E7647"]
block_sample_size = 2
cooldown_period_blocks = 12
min_number_of_operators = 1
max_number_of_operators = 2
private_trap = true
```

### 5. APPLY TRAP

```
DROSERA_PRIVATE_KEY=$OPERATOR_PK drosera apply
```

---

## 🧪 TEST FLOW

### A. Before anything — check balances

```
cast call $TOKEN_ADDRESS "balanceOf(address)(uint256)" SAFE
cast call $TOKEN_ADDRESS "balanceOf(address)(uint256)" FUNDING
```

### B. Trigger initial data sample

```
drosera collect autotopup
```

### C. Simulate SAFE spending (owner runs locally)

```
cast send $TOKEN_ADDRESS \
"transfer(address,uint256)" 0xDeadBeef... $(cast to-wei 600000 eth) \
--rpc-url $RPC --private-key $SAFE_PK
```

### D. Force trap evaluation

```
drosera dryrun
# or
drosera collect autotopup
```

### E. Confirm top-up success

```
cast call $TOKEN_ADDRESS "balanceOf(address)(uint256)" SAFE
cast call $TOKEN_ADDRESS "balanceOf(address)(uint256)" FUNDING
cast logs --rpc-url $RPC $RESPONDER_ADDRESS
```

---

## 📦 Available Helper Scripts

* Full `approve.js` (ethers.js)
* `test_trap.sh` to simulate spend + dryrun automatically
* Permit-based gasless approval (EIP-2612)
* ZIP packaging for direct Remix import

---

**Reply:**
`SEND ALL HELPERS` → include every helper script
`ONLY permit + bash test + zip format` → compile specific tools instantly

<img width="1599" height="739" alt="image" src="https://github.com/user-attachments/assets/bcca7ecc-cd5c-42ef-aed7-adc866423616" />

