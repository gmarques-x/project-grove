-- Project Grove · yazi's top bar, drawn like the Starship prompt: a rounded
-- start, the user (aqua), an arrow into the folder (green), an arrow into a
-- short yellow end. A line runs under it. Colors: theme/everforest-dark-medium.
-- Terminal.app can't draw Nerd Font glyphs, so it gets the same blocks without
-- them, like starship-plain.toml.

local AQUA, GREEN, YELLOW, BG0, BORDER = "#83C092", "#A7C080", "#DBBC7F", "#2D353B", "#475258"

local plain = os.getenv("TERM_PROGRAM") == "Apple_Terminal"
local OPEN = plain and " " or "\u{e0b6}"   -- rounded start
local ARROW = plain and " " or "\u{e0b0}"  -- arrow between blocks
local CLOSE = plain and " " or "\u{e0b4}"  -- rounded end
local USER = plain and " " or "\u{f179} "  -- Apple, as in the prompt

-- The hovered row's rounded ends (theme.toml) become plain ends there too.
if plain then
	th.indicator.padding = { open = " ", close = " " }
end

local function seg(text, fg, bg)
	local s = ui.Span(text):fg(fg)
	return bg and s:bg(bg) or s
end

-- The bar replaces yazi's plain path; flags (search, filter, find) stay on it.
function Header:cwd()
	local max = self._area.w - self._right_width
	if max <= 0 then
		return ""
	end
	local user = " " .. USER .. (ya.user_name() or os.getenv("USER") or "") .. " "
	local fixed = ui.Line({ OPEN, user, ARROW, "  ", ARROW, " ", CLOSE }):width()
	local path = ui.truncate(ya.readable_path(tostring(self._current.cwd)) .. self:flags(),
		{ max = math.max(1, max - fixed), rtl = true })
	return ui.Line {
		seg(OPEN, AQUA),
		seg(user, BG0, AQUA),
		seg(ARROW, AQUA, GREEN),
		seg(" " .. path .. " ", BG0, GREEN),
		seg(ARROW, GREEN, YELLOW),
		seg(" ", BG0, YELLOW),
		seg(CLOSE, YELLOW),
	}
end

-- Two rows: the bar, then the line.
function Header:redraw()
	local right = self:children_redraw(self.RIGHT)
	self._right_width = right:width()
	local left = self:children_redraw(self.LEFT)
	local a = self._area
	local bar = ui.Rect { x = a.x, y = a.y, w = a.w, h = 1 }
	local rule = ui.Rect { x = a.x, y = a.y + 1, w = a.w, h = 1 }
	return {
		ui.Line(left):area(bar),
		ui.Line(right):area(bar):align(ui.Align.RIGHT),
		ui.Line(string.rep("─", a.w)):fg(BORDER):area(rule),
	}
end

-- yazi's layout (v26.9.1 preset) with a two-row header.
function Root:layout()
	self._chunks = ui.Layout()
		:direction(ui.Layout.VERTICAL)
		:constraints({
			ui.Constraint.Length(2),
			ui.Constraint.Length(Tabs.height()),
			ui.Constraint.Fill(1),
			ui.Constraint.Length(1),
		})
		:split(self._area)
end
