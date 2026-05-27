// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DemoERC721} from "../src/DemoERC721.sol";
import {DemoERC1155} from "../src/DemoERC1155.sol";

contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        DemoERC721 erc721 = new DemoERC721(
            "Pharos Demo 721",
            "PD721",
            "ipfs://bafy-placeholder/",
            deployer
        );

        DemoERC1155 erc1155 = new DemoERC1155(
            "ipfs://bafy-placeholder/{id}.json",
            deployer
        );

        // Mint a handful of tokens to the deployer for sanity testing.
        erc721.mint(deployer);   // tokenId 1
        erc721.mint(deployer);   // tokenId 2
        erc721.mint(deployer);   // tokenId 3

        erc1155.mint(deployer, 1, 100);
        erc1155.mint(deployer, 2, 50);

        vm.stopBroadcast();

        console.log("DemoERC721 deployed at:", address(erc721));
        console.log("DemoERC1155 deployed at:", address(erc1155));
        console.log("Deployer:", deployer);
    }
}
