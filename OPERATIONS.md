# OPERATIONS
## 2024.06.14
- `DeployFraxOFTProtocol()`
    - Deploy Mode: FRAX, sFRAX, sfrxETH, FXS
    - Destinations: Ethereum, Base, Blast, Metis

# 2024.06.20
- `DeployFraxOFTProtocol()`
    - Deploy Sei: FRAX, sFRAX, sfrxETH, FXS
    - Destinations: Ethereum, Base, Blast, Metis, Mode

## 2024.06.21
- `FixDeployDVNs()`
    - Re-submit msig txs @ v1.0.2
    - Destinations: Ethereum, Base, Blast, Metis
    - Note: Mode => Sei D/c
## 2024.06.27
- `SubmitSend()`
    - Ethereum => Mode (FRAX, sFRAX, sfrxETH, FXS)
    - Base => Mode (FRAX, sFRAX, sfrxETH, FXS)
    - Blast => Mode (FRAX, sFRAX, sfrxETH, FXS)
    - Metis => (Mode, Blast) (FRAX, sFRAX, sfrxETH, FXS)
    - Mode => (Ethereum, Base, Blast, Metis) (FRAX, sFRAX, sfrxETH, FXS)

# 2024.06.28
- `DeployFrxEthFpi()`
    - Deploy Mode: frxETH, FPI
    - Destinations: Ethereum, Base, Blast, Metis

# 2024.07.01
- `DeployFrxEthFpi()`
    - Deploy Sei: frxEth, FPI
    - Destinations: Ethereum, Base, Blast, Metis

# 2024.07.02
- `FixDVNs()`
    - modify the Sei configured DVNs to use the Horizen DVN instead of the Nethermind DVN

# 2024.07.03
- `FixDVNs()`
    - Fix Mode => Sei DVN

# 2024.07.09
- `DeployFraxOFTProtocol()`
    - Deploy Fraxtal: FRAX, sFRAX, frxETH, sfrxETH, FXS, FPI
    - Destinations: Ethereum, Base, Blast, Metis, Mode, Sei