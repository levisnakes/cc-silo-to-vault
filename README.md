# CC Silo to Vault

ComputerCraft program that moves everything from one storage block (such as an item silo) into another (such as a Create item vault), but leaves behind Create packages addressed to the names you list.

## Install

On the computer:

```
wget https://raw.githubusercontent.com/levisnakes/cc-silo-to-vault/main/silo_to_vault.lua startup.lua
```

## Settings

Run `edit startup.lua` and change the SETTINGS box at the top:

- `PULL_FROM`: the block to take items from
- `PUSH_TO`: the block to put items into
- `SKIP_PACKAGES`: package addresses to leave alone
- `WAIT_TIME`: how long to wait between checks when there's nothing to move

Right-click a wired modem to see the name of the block it's attached to. Both blocks must be on the same cable network.
