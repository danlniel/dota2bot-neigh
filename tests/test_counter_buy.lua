-- Run from repo root: luajit tests/test_counter_buy.lua
package.path = package.path .. ';./bots/FunLib/?.lua'
local RB = require('reactive_buy')

-- lockdown buyers: pos2 then pos3 then pos1, bots only, first two win
local allBots = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true }
assert(RB.IsLockdownBuyer(2, allBots, 2) == true, 'mid buys first')
assert(RB.IsLockdownBuyer(3, allBots, 2) == true, 'offlane buys second')
assert(RB.IsLockdownBuyer(1, allBots, 2) == false, 'carry keeps farming build')
assert(RB.IsLockdownBuyer(4, allBots, 2) == false, 'supports never assigned')
assert(RB.IsLockdownBuyer(5, allBots, 2) == false, 'supports never assigned')

-- human mid: the carry steps in so the team still gets two answers
local humanMid = { [1] = true, [3] = true, [4] = true, [5] = true }
assert(RB.IsLockdownBuyer(3, humanMid, 2) == true)
assert(RB.IsLockdownBuyer(1, humanMid, 2) == true)

-- humans on mid and offlane: only the carry bot is left
local humanMidOff = { [1] = true, [4] = true, [5] = true }
assert(RB.IsLockdownBuyer(1, humanMidOff, 2) == true)

-- one wanted: only the mid
assert(RB.IsLockdownBuyer(2, allBots, 1) == true)
assert(RB.IsLockdownBuyer(3, allBots, 1) == false)

-- item choice: STR -> disarm, everyone else -> silence
assert(RB.LockdownItemFor(true) == 'item_heavens_halberd')
assert(RB.LockdownItemFor(false) == 'item_orchid')

-- queue front: reverse-order list, the LAST entry is what's bought next
local q = { 'item_butterfly', 'item_satanic', 'item_black_king_bar' }
assert(RB.QueueFront(q, 'item_orchid') == true)
assert(q[#q] == 'item_orchid', 'counter becomes the next buy')
assert(q[#q - 1] == 'item_black_king_bar', 'interrupted target resumes after')
assert(#q == 4)

-- already next: no-op
assert(RB.QueueFront(q, 'item_orchid') == false)
assert(#q == 4)

-- planned later in the build: moved up, never duplicated
local q2 = { 'item_sheepstick', 'item_butterfly', 'item_black_king_bar' }
assert(RB.QueueFront(q2, 'item_sheepstick') == true)
assert(#q2 == 3, 'moved, not duplicated')
assert(q2[3] == 'item_sheepstick' and q2[2] == 'item_black_king_bar'
	and q2[1] == 'item_butterfly')

-- empty list
local q3 = {}
assert(RB.QueueFront(q3, 'item_ghost') == true and q3[1] == 'item_ghost')

print('test_counter_buy: all assertions passed')
