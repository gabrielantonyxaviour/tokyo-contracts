interface IInterchainQueryRouter {
    /**
     * @param _destinationDomain Domain of destination chain
     * @param target The address of the contract to query on destination chain.
     * @param queryData The calldata of the view call to make on the destination
     * chain.
     * @param callback Callback function selector on `msg.sender` and optionally
     * abi-encoded prefix arguments.
     * @return messageId The ID of the Hyperlane message encoding the query.
     */
    function query(
        uint32 _destinationDomain,
        address target,
        bytes calldata queryData,
        bytes calldata callback
    ) external returns (bytes32);
}
