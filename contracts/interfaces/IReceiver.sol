interface IReceiver {
    function getLatestPromotionDeployment(address claimer)
        external
        view
        returns (address);
}
