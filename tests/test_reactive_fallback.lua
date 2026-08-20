-- Run from repo root: luajit tests/test_reactive_fallback.lua
package.path = package.path .. ';./bots/FunLib/?.lua'
local RB = require('reactive_buy')

-- stub component tree: recipes are leaves, hood nests inside pipe
local tree = {
	item_blade_mail = { 'item_broadsword', 'item_chainmail' },
	item_pipe = { 'item_hood_of_defiance', 'item_headdress', 'item_recipe_pipe' },
	item_hood_of_defiance = { 'item_cloak', 'item_ring_of_health' },
	item_headdress = { 'item_ring_of_regen', 'item_recipe_headdress' },
}
local function getComponents(name)
	return tree[name] or { name }
end

-- flatten: nested composites fully decompose, recipes kept as leaves
local flat = RB.FlattenComponents('item_pipe', getComponents)
assert(#flat == 5, 'expected 5 leaves, got ' .. #flat)
assert(flat[1] == 'item_cloak' and flat[2] == 'item_ring_of_health',
	'hood must decompose depth-first')
assert(flat[5] == 'item_recipe_pipe', 'recipe kept as leaf')

-- flatten: basic item returns itself
local basic = RB.FlattenComponents('item_ghost', getComponents)
assert(#basic == 1 and basic[1] == 'item_ghost')

-- shop gate: a secret-shop component blocks unless at the secret shop
local function isSecret(name) return name == 'item_ring_of_health' end
assert(RB.CanBuyComponentsNow(flat, isSecret, false) == false)
assert(RB.CanBuyComponentsNow(flat, isSecret, true) == true)
assert(RB.CanBuyComponentsNow({ 'item_cloak' }, isSecret, false) == true)

-- missing: owned components are subtracted once each
local missing = RB.MissingComponents(
	{ 'item_broadsword', 'item_chainmail' }, { item_chainmail = 1 })
assert(#missing == 1 and missing[1] == 'item_broadsword')

-- missing: duplicate components need duplicate ownership
missing = RB.MissingComponents(
	{ 'item_ring_of_regen', 'item_ring_of_regen' }, { item_ring_of_regen = 1 })
assert(#missing == 1 and missing[1] == 'item_ring_of_regen')

print('test_reactive_fallback: all assertions passed')
