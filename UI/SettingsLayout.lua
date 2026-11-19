-- Pure layout calculations for settings widgets; no state changes or game APIs.
local ADDON, NS = ...
local SettingsLayout = {}
NS.SettingsLayout = SettingsLayout

---@alias QuestAutomator_SettingsPixels number UI units (not physical screen pixels).
---@alias QuestAutomator_SettingsOptionIndex integer Position within one radio group's values.
---@alias QuestAutomator_SettingsWidget table WoW frame with optional Layout(width), GetHeight/SetHeight/SetWidth.
---@class QuestAutomator_SettingsRowEntry
---@field widget QuestAutomator_SettingsWidget
---@field indent QuestAutomator_SettingsPixels Relative to the section content's left edge.
---@field gap QuestAutomator_SettingsPixels Space above this row.
---@field minHeight QuestAutomator_SettingsPixels? Minimum allocated height.
---@field x QuestAutomator_SettingsPixels? Calculated horizontal offset.
---@field y QuestAutomator_SettingsPixels? Calculated downward offset.
---@field width QuestAutomator_SettingsPixels? Calculated allocated width.
---@field height QuestAutomator_SettingsPixels? Calculated allocated height.
---@class QuestAutomator_SettingsFlowCell
---@field x QuestAutomator_SettingsPixels
---@field y QuestAutomator_SettingsPixels Downward offset from the option group's top.
---@field width QuestAutomator_SettingsPixels Available width for radio plus label.
---@field height QuestAutomator_SettingsPixels
---@class QuestAutomator_SettingsFlowPlan
---@field cells QuestAutomator_SettingsFlowCell[]
---@field height QuestAutomator_SettingsPixels Total occupied height.

---@param availableWidth QuestAutomator_SettingsPixels
---@param naturalWidths QuestAutomator_SettingsPixels[]
---@param measureHeight fun(index: QuestAutomator_SettingsOptionIndex, width: QuestAutomator_SettingsPixels): QuestAutomator_SettingsPixels
---@return QuestAutomator_SettingsFlowPlan
function SettingsLayout.Flow(availableWidth, naturalWidths, measureHeight)
	availableWidth = math.max(1, availableWidth)
	local cells = {}
	local x, y, lineHeight = 0, 0, 0
	local columnGap, rowGap = 14, 6
	for index, naturalWidth in ipairs(naturalWidths) do
		local width = math.min(availableWidth, naturalWidth)
		if x > 0 and x + width > availableWidth then
			x, y, lineHeight = 0, y + lineHeight + rowGap, 0
		end
		local height = math.max(16, measureHeight(index, width))
		cells[index] = {x = x, y = y, width = width, height = height}
		x = x + width + columnGap
		lineHeight = math.max(lineHeight, height)
	end
	return {cells = cells, height = y + lineHeight}
end

---@param entries QuestAutomator_SettingsRowEntry[]
---@param availableWidth QuestAutomator_SettingsPixels
---@param topInset QuestAutomator_SettingsPixels
---@return QuestAutomator_SettingsPixels bottom
function SettingsLayout.Stack(entries, availableWidth, topInset)
	local bottom = topInset
	for _, entry in ipairs(entries) do
		local width = math.max(1, availableWidth - entry.indent)
		local height = entry.widget.Layout and entry.widget:Layout(width) or entry.widget:GetHeight()
		height = math.max(entry.minHeight or 0, height or 0)
		entry.widget:SetWidth(width)
		entry.widget:SetHeight(height)
		bottom = bottom + entry.gap
		entry.x, entry.y, entry.width, entry.height = entry.indent, bottom, width, height
		bottom = bottom + height
	end
	return bottom
end