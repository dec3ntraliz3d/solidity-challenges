# Staking contract with Permit2

### This staking contract is a simplified version of synthetix original staking contract. I addition to that I have implemented Permit2 which was recently published by Uniswap lab.

### If you look at the staking contract you will see there are two option to stake.

### First option : Simple stake() where user need to first send an approval transaction before staking.

### Second option: Staking with permit2 where user can just sign the approval message. This can be implemented with any ERC20 token ( even the ones that don't support permit)
