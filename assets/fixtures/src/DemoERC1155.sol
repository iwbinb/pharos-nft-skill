// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DemoERC1155 is ERC1155, Ownable {
    constructor(string memory uri_, address owner_) ERC1155(uri_) Ownable(owner_) {}

    function mint(address to, uint256 id, uint256 amount) external onlyOwner {
        _mint(to, id, amount, "");
    }

    function mintBatch(address to, uint256[] calldata ids, uint256[] calldata amounts) external onlyOwner {
        _mintBatch(to, ids, amounts, "");
    }

    function airdrop(address[] calldata recipients, uint256 id, uint256 amount) external onlyOwner {
        for (uint256 i = 0; i < recipients.length; ++i) {
            _mint(recipients[i], id, amount, "");
        }
    }

    function setURI(string calldata newuri) external onlyOwner {
        _setURI(newuri);
    }
}
