local M = {}

local CACHE_DIR = os.getenv("HOME") .. "/.cache/yazi/to-pdf-preview"

local set_state = ya.sync(function(state, key, value) state[key] = value end)
local get_state = ya.sync(function(state, key) return state[key] end)

local function get_page_count(pdf_path)
	local cache_key = "page_count_" .. tostring(pdf_path)
	local cached = get_state(cache_key)
	if cached then return cached end

	local output = Command("pdfinfo"):arg(tostring(pdf_path)):output()
	if not output then return nil end

	local count = tonumber(output.stdout:match("Pages:%s*(%d+)"))
	if count then set_state(cache_key, count) end
	return count
end

local function fail(job, s)
	ya.preview_widget(job, ui.Text.parse(s):area(job.area):wrap(ui.Wrap.YES))
end

-- Where a converted (non-native) source lands.
local function converted_path(job)
	return CACHE_DIR .. "/" .. job.file.name:gsub("%.[^%.]+$", ".pdf")
end

-- The PDF to render, converting the source first when it isn't already one.
-- Shared by peek and preload so the conversion rules live in one place.
function M:ensure_pdf(job)
	if job.mime == "application/pdf" then
		return tostring(job.file.url)
	end

	if not job.args or not job.args[1] then
		return nil, "No command specified. Usage: to-pdf-preview -- command arg1 arg2..."
	end

	local pdf_path = converted_path(job)
	if fs.cha(Url(pdf_path)) then
		return pdf_path
	end

	local ok, err = self:convert_to_pdf(job, pdf_path, job.args[1])
	if not ok then
		return nil, err or "Failed to convert to PDF"
	end
	return pdf_path
end

-- Render a single page to `cache`. On failure returns which stage failed, plus
-- the page count parsed out of stderr when the request was past the last page.
---@return boolean ok, string? stage, integer pages
local function render_page(pdf_path, page, cache)
	local output = Command("pdftoppm")
		:arg({
			"-singlefile", "-jpeg",
			"-jpegopt", "quality=" .. (rt.preview.image_quality or 90),
			"-r", 300,
			"-f", page, "-l", page,
			pdf_path,
		})
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()

	if not output or not output.status.success then
		return false, "render", tonumber(output and output.stderr:match("the last page %((%d+)%)")) or 0
	elseif not fs.write(cache, output.stdout) then
		return false, "write", 0
	end
	return true, nil, 0
end

function M:peek(job)
	local pdf_path, err = self:ensure_pdf(job)
	if not pdf_path then
		return fail(job, err)
	end

	local start, cache = os.clock(), ya.file_cache(job)
	if not cache then return end

	if fs.cha(cache) then
		ya.sleep(math.max(0, 30 / 1000 + start - os.clock()))
		self:show_with_counter(job, cache, pdf_path)
		return
	end

	local ok, stage, pages = render_page(pdf_path, (job.skip or 0) + 1, cache)
	if not ok then
		if stage == "write" then
			return fail(job, "Failed to write image cache")
		elseif job.skip > 0 and pages > 0 then
			ya.emit("peek", { math.max(0, pages - 1), only_if = job.file.url, upper_bound = true })
		end
		return
	end

	ya.sleep(math.max(0, 30 / 1000 + start - os.clock()))
	self:show_with_counter(job, cache, pdf_path)
end

-- Warms both stages ahead of the cursor: the LibreOffice conversion and the
-- first page's JPEG. Renders nothing itself.
function M:preload(job)
	local cache = ya.file_cache { file = job.file, skip = 0 }
	if not cache then
		return true
	elseif fs.cha(cache) then
		return true -- page 1 already warm
	end

	local pdf_path = self:ensure_pdf(job)
	if not pdf_path then
		return true -- unconvertible; peek will report why
	end

	render_page(pdf_path, 1, cache)
	return true
end

function M:show_with_counter(job, cache, pdf_path)
	local total_pages = get_page_count(pdf_path)

	if not total_pages then
		ya.image_show(cache, job.area)
		ya.preview_widget(job, {})
		return
	end

	local current_page = math.max(1, math.min((job.skip or 0) + 1, total_pages))
	local image_height = math.max(1, job.area.h - 1)

	local rendered_rect = ya.image_show(cache, ui.Rect({
		x = job.area.x, y = job.area.y,
		w = job.area.w, h = image_height,
	}))

	local actual_image_height = rendered_rect and rendered_rect.h or image_height
	local counter_text = string.format("Page %d/%d", current_page, total_pages)
	local padding = math.max(0, math.floor((job.area.w - #counter_text) / 2))

	ya.preview_widget(job, {
		ui.Text({ ui.Line({ ui.Span(string.rep(" ", padding)), ui.Span(counter_text) }) })
			:area(ui.Rect({
				x = job.area.x, y = job.area.y + actual_image_height,
				w = job.area.w, h = job.area.h - actual_image_height,
			}))
			:wrap(ui.Wrap.NO),
	})
end

function M:convert_to_pdf(job, pdf_path, command)
	-- Convert into a private directory and publish with one rename. A preload
	-- and a peek can now be in flight for the same file at the same time, and
	-- both write the same output name; without this they would interleave and
	-- a reader could see a half-written PDF.
	local tmp_dir = string.format("%s/.tmp-%d-%d", CACHE_DIR, os.time(), math.random(100000, 999999))
	Command("mkdir"):arg({ "-p", tmp_dir }):output()

	local output = Command("sh")
		:arg({ "-c", command, "sh", tostring(job.file.url) })
		:env("OUTDIR", tmp_dir .. "/")
		:env("CLICOLOR_FORCE", "1")
		:output()

	local produced = tmp_dir .. "/" .. job.file.name:gsub("%.[^%.]+$", ".pdf")
	if not output or not output.status.success or not fs.cha(Url(produced)) then
		Command("rm"):arg({ "-rf", tmp_dir }):output()
		return false, "Command failed: " .. command
	end

	Command("mv"):arg({ "-f", produced, pdf_path }):output()
	Command("rm"):arg({ "-rf", tmp_dir }):output()

	if not fs.cha(Url(pdf_path)) then
		return false, "Failed to publish converted PDF"
	end
	return true
end

function M:seek(job)
	local h = cx.active.current.hovered
	if h and h.url == job.file.url then
		local step = ya.clamp(-1, job.units, 1)
		ya.emit("peek", { math.max(0, cx.active.preview.skip + step), only_if = job.file.url })
	end
end

return M
