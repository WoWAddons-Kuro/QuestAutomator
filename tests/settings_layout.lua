-- Pure settings geometry tests; run from workspace root using lua5.1.
local NS = {}
assert(loadfile('QuestAutomator/UI/SettingsLayout.lua'))('QuestAutomator', NS)
local Layout = NS.SettingsLayout
local function assertFlow(width, widths)
	local plan = Layout.Flow(width, widths, function(i, cellWidth)
		return math.ceil(widths[i] / cellWidth) * 12
	end)
	assert(#plan.cells == #widths)
	local previous
	for _, cell in ipairs(plan.cells) do
		assert(cell.x >= 0 and cell.width > 0 and cell.x + cell.width <= width)
		assert(cell.y >= 0 and cell.height >= 16 and cell.y + cell.height <= plan.height)
		if previous then
			assert(cell.y >= previous.y)
			if cell.y == previous.y then assert(cell.x >= previous.x + previous.width + 14)
			else assert(cell.y >= previous.y + previous.height + 6) end
		end
		previous = cell
	end
	return plan
end
local plan = assertFlow(220, {100, 100, 100})
assert(plan.cells[1].y == plan.cells[2].y and plan.cells[3].y > plan.cells[2].y)
assert(assertFlow(560, {80, 90, 110, 70, 70, 100}).height >= 38)
assert(assertFlow(100, {300, 40}).cells[2].y >= 42)
assert(Layout.Flow(300, {}, function() error('should not measure empty list') end).height == 0)
for width = 80, 620, 20 do
	assertFlow(width, {78, 100, 94, 140, 190, 260})
	assertFlow(width, {540, 1000, 16})
end
print('PASS radio packing: bounds, label wrapping, row gaps, long choices and varied widths')

local function widget(measuredHeight)
	return {Layout = function(_, width) return measuredHeight + (width < 200 and 30 or 0) end,
		SetWidth = function(self, width) self.width = width end,
		SetHeight = function(self, height) self.height = height end}
end
local entries = {
	{widget = widget(58), minHeight = 40, indent = 0, gap = 6},
	{widget = widget(16), minHeight = 26, indent = 20, gap = 8},
	{widget = widget(60), minHeight = 14, indent = 0, gap = 10},
}
local bottom = Layout.Stack(entries, 560, 24)
assert(entries[1].height == 58 and entries[2].height == 26 and entries[3].height == 60)
for index, entry in ipairs(entries) do
	assert(entry.width == 560 - entry.indent)
	assert(entry.widget.height == entry.height and entry.widget.width == entry.width)
	if index > 1 then assert(entry.y == entries[index - 1].y + entries[index - 1].height + entry.gap) end
end
assert(bottom == entries[3].y + entries[3].height)
local narrowBottom = Layout.Stack(entries, 180, 24)
assert(narrowBottom > bottom)
assert(entries[2].x == 20 and entries[3].x == 0, 'indentation drift')
print('PASS stack: measured row/holder/border agreement, minimum sizes and stable indentation')