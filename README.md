# DecentralizedStableCoin

Welcome to **DecentralizedStableCoin (DSC)**, a decentralized stablecoin protocol designed to maintain a 1:1 peg with the US Dollar. This protocol leverages exogenous crypto collateral and an algorithmic mechanism to ensure stability.

## Overview

**DecentralizedStableCoin** (DSC) is an ERC20 token that functions as a stable digital currency, pegged to $1 USD. It operates under the governance of the **DSCEngine** smart contract, which handles the minting and burning of DSC based on collateral and algorithmic rules.

## Key Features

- **Collateral**: Exogenous crypto assets
- **Minting Mechanism**: Decentralized and algorithmic, governed by the DSCEngine smart contract
- **Stability**: Pegged to USD, maintaining a value of $1 = 1 DSC

## Smart Contract Ownership

The DSC token is managed by the **DSCEngine** smart contract, which is responsible for:
- Minting new DSC tokens when collateral requirements are met
- Burning DSC tokens when users redeem them for collateral
- Liquidating undercollateralised sers

## How It Works

1. **Minting DSC**:
   - Users deposit exogenous crypto collateral into the DSCEngine.
   - Based on predefined rules, DSC tokens are minted and issued to the user.
   
2. **Maintaining Stability**:
   - The algorithmic mechanism adjusts the supply of DSC to ensure its value remains pegged to $1 USD.
   - This involves burning or minting DSC based on market conditions and collateral status.

3. **Redeeming DSC**:
   - Users can redeem DSC tokens for the underlying crypto collateral through the DSCEngine.
   - The DSCEngine burns the redeemed DSC, reducing the circulating supply.

4. **Liquidation**:
   - Users can liquidate other users that have borrowed DSC with less collateral.

## Development

- **Smart Contracts**: Located in the `contracts` directory
- **Tests**: Unit tests are provided in the `test` directory
- **Deploy Scripts**: Located in the `scripts` directory
- **Utilized private key encryption with Cast**: 
  Preferrably in your local terminal and not a text editor like VS Code.
  ```
    cast wallet import your-account-name --interactive
    Enter private key:
    Enter password:
    `your-account-name` keystore was saved successfully. Address: address-corresponding-to-private-key
    ```

    `your-account-name` will be the name given to that private key account in cast
    Save the `address` since you need it to run a deploy script such as:
    ```
    forge script <script> --rpc-url <rpc_url> --account <account_name> --sender <address> --broadcast
    ```

    This `address` will be the public key of the private key you've just encrypted.

    In this case, as the `address` args after `--sender`
    
    Watch how: [Cyfrin Audits](https://www.youtube.com/watch?v=VQe7cIpaE54)
    and [this](https://www.youtube.com/watch?v=8JMwIyyfyT0)


    You can also have a `.paswsord` file (add to `.gitignore`) where you save the password to encryped private key associated with the project or directly in `.env` (incase you forget to add `.password` to `.gitignore`)

    **Question**: How can I use encrypted keys in for `deployerKey` in `helperConfig.s.sol` without needing `.env`:
    ```
    function getSepoliaEthConfig() public view returns (NetworkConfig memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306, // ETH / USD https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43, // BTC / USD https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063, // Gotten from?
            deployerKey: vm.envUint("SEPOLIA_PRIVATE_KEY") // Reads SEPOLIA_PRIVATE_KEY from .env file. **PRIVATE STUFF!**
            
        });
    ```
   **UPDATE**
   Fianlly found a way to do this thanks to Rafael Quintero. Here's what you have to do:
   1. Store the path to your encrypted key in your `.env` as such
      ```
      ETH_KEYSTORE_ACCOUNT=~/.foundry/keystores/defiProtocol2.json
      ```
      To find the path to your encrpted key, run ```cd .foundry/keystores/``` in your home directory. Once in `ls` to view encrypted keys. Concatenate it like for `ETH_KEYSTORE_ACCOUNT` and add a .json
      
   2. Check myyyy `HelperConfig.s.sol` and `DeployDSC.s.sol` to see how the codes were refactored.
   3. Run your deploy with
      ```
      forge script script/DeployDSC.s.sol:DeployDSC --fork-url $SEPOLIA --account defiProtocol2 --sender <public-key-of-encrypted-private-key>  --broadcast 
      ```
   4. 

## Author

- **Ikpong Joseph**

## Contributing

Contributions are welcome! Reach out to me via [email](ikpongjos@gmail.com).

---

**Note**: This README provides a high-level overview of the DecentralizedStableCoin protocol. For detailed technical documentation, please refer to the code and comments within the smart contracts.

---

Thank you for exploring DecentralizedStableCoin! 🚀
