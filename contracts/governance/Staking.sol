// contract Staking {

//     uint256[] traunches = [10, 100, 1000, 10000, 100000];
//     mapping(uint256=>bool) validTraunches;

//     // always
//     mapping(address=>mapping(uint256=>List)) stakes;

//     // head = 0 && tail = 0 if list is empty

//     // Linked List
//     // Always sorted by time
//     // Always one traunch
//     struct List {
//         Stake head;
//         Stake tail;
//     }

//     // Linked List Node
//     struct Stake {
//         uint256 amount;
//         uint256 time;
//         Stake next;
//     }
//     // https://programtheblockchain.com/posts/2018/03/30/storage-patterns-doubly-linked-list/

//     // AddsSstake to end of List
//     // Assume adding a new item is always the latest time
//     function _addStake(List storage list, uint256 amount, uint256 time) internal {
//         // create new node
//         Stake storage newStake = Stake({amount: amount, time: time, next: 0});
//         // check if list is empty
//         if (list.head == 0) {
//             list.head = newStake;
//         }
//         else {
//             // set previous tail to new node
//             list.tail.next = newStake;
//         }
//         // set tail in list
//         list.tail = newStake;
//     }

//     // Remove first Stake from List and return
//     function _removeStake(List storage list) internal returns (Stake) {
//         // check if list has no nodes
//         if (list.head == 0) {
//             return 0;
//         }
//         // store head
//         List head = list.head;

//         // check if no more nodes
//         if (head.next == 0) {
//             list.head = 0;
//             list.tail = 0;
//             return head;
//         }
//         // set new head to head.next
//         list.head = head.next;

//         // delete old head from list
//         delete list.head;

//         // return Stake
//         return head;
//     }

//     // because traunches is fixed length, we know the loop will always have enough gas
//     function _findFirstUnlockTraunch(address account) public returns (uint256) {
//         // loop through all traunches
//         // for each traunch:
//         // 1) check if first item unlock < block.timestamp
//         // 2) if true, return traunch
//         // return 0 or revert
//     }

//     // we know that
//     // what happens if we stake twice in the same block?
//     // ->
//     function _stake(address account, uint256 amount, uint256 traunch) internal {
//         require(validTraunches[traunch], "invalid traunch");
//         // TODO: transfer tokens
//         // get list for traunch
//         List storage list = stakes[account][traunch];
//         // add stake to list
//         // calculate time as timestamp + traunch
//         _addStake(list, amount, block.timestamp.add(traunch));
//     }

//     function _unstake(address account, uint256 traunch) internal {
//         require(validTraunches[traunch], "invalid traunch");
        
//         List storage list = stakes[account][traunch];
//         // check account has stake in this traunch
//         require(list.head != 0, "no stake in this traunch");
//         // check if stake is locked
//         require(list.head.time > block.timestamp, "cannot unstake: stake is locked");
//         // always unstake first item
//         Stake memory stake = _unstake(list);
//         // TODO: transfer tokens
//     }
// }