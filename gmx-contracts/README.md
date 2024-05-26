


# 执行流程
* 查询价格：`VaultReader.getVaultTokenInfoV4`
* 申请买入看多的衍生品：`PositionRouter.createIncreasePosition`
* 申请买入看多的衍生品(支付ETh)：`PositionRouter.createIncreasePositionETH`
* 查询“买入衍生品”的未通过的申请记录的key索引及总记录数：`PositionRouter.getRequestQueueLengths`
* 根据索引id查询“买入看多的衍生品”的申请记录的key值：`PositionRouter.increasePositionRequestKeys`
* 根据key查询“买入看多的衍生品”的申请记录：`PositionRouter.increasePositionRequests`
* 根据key取消“买入看多的衍生品”的申请记录：`PositionRouter.cancelIncreasePosition`
* 执行多条“买入看多的衍生品”的申请记录，直到指定的key索引：`PositionRouter.cancelIncreasePositions`
* 根据指定的key执行“买入看多的衍生品”的申请记录：`PositionRouter.cancelIncreasePosition`






* 根据key查询“买入看空的衍生品”的申请记录：`PositionRouter.decreasePositionRequests`

* 查询当前持仓记录列表（即申请已通过）：`Reader.getPositions`
