local M = {}

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

function M:peek(job)
	local pdf_path
	local is_native_pdf = job.mime == "application/pdf"

	if is_native_pdf then
		pdf_path = tostring(job.file.url)
	else
		if not job.args or not job.args[1] then
			return fail(job, "No command specified. Usage: to-pdf-preview -- command arg1 arg2...")
		end

		local pdf_name = job.file.name:gsub("%.[^%.]+$", ".pdf")
		local pdf_cache_dir = os.getenv("HOME") .. "/.cache/yazi/to-pdf-preview"
		pdf_path = pdf_cache_dir .. "/" .. pdf_name

		if not fs.cha(Url(pdf_path)) then
			local ok, err = self:convert_to_pdf(job, pdf_path, job.args[1])
			if not ok then
				return fail(job, err or "Failed to convert to PDF")
			end
		end
	end

	local start, cache = os.clock(), ya.file_cache(job)
	if not cache then return end

	if fs.cha(cache) then
		ya.sleep(math.max(0, 30 / 1000 + start - os.clock()))
		self:show_with_counter(job, cache, pdf_path)
		return
	end

	local page_num = (job.skip or 0) + 1
	local output = Command("pdftoppm")
		:arg({
			"-singlefile", "-jpeg",
			"-jpegopt", "quality=" .. (rt.preview.image_quality or 90),
			"-r", 300,
			"-f", page_num, "-l", page_num,
			pdf_path,
		})
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()

	if not output or not output.status.success then
		local pages = tonumber(output and output.stderr:match("the last page %((%d+)%)")) or 0
		if job.skip > 0 and pages > 0 then
			ya.emit("peek", { math.max(0, pages - 1), only_if = job.file.url, upper_bound = true })
		end
		return
	end

	if fs.write(cache, output.stdout) then
		ya.sleep(math.max(0, 30 / 1000 + start - os.clock()))
		self:show_with_counter(job, cache, pdf_path)
	else
		return fail(job, "Failed to write image cache")
	end
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
	local pdf_cache_dir = os.getenv("HOME") .. "/.cache/yazi/to-pdf-preview"
	Command("mkdir"):arg({ "-p", pdf_cache_dir }):output()

	local output = Command("sh")
		:arg({ "-c", command, "sh", tostring(job.file.url) })
		:env("OUTDIR", pdf_cache_dir .. "/")
		:env("CLICOLOR_FORCE", "1")
		:output()

	if not output or not output.status.success then
		return false, "Command failed: " .. command
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
