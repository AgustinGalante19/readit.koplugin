--[[--
This is a debug plugin to test Plugin functionality.

@module koplugin.HelloWorld
--]]

local Dispatcher = require("dispatcher") -- luacheck:ignore
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local util = require("util")
local _ = require("gettext")
local json = require("json")
local http = require("socket.http")
local ltn12 = require("ltn12")
local logger = require("logger")

local Readit = WidgetContainer:extend {
  name = "readit",
  is_doc_only = false,
}

function Readit:onDispatcherRegisterActions()
  Dispatcher:registerAction("readit_action",
    { category = "none", event = "ReadIt", title = _("Read It"), general = true, })
end

local function postJSON(bodyTable)
  local body = json.encode(bodyTable)
  local response = {}

  local ok, status = http.request {
    url = "https://v5jdc5vc-3000.brs.devtunnels.ms/api/koreader/hash",
    method = "POST",
    headers = {
      ["Content-Type"] = "application/json",
      ["Content-Length"] = #body,
    },
    source = ltn12.source.string(body),
    sink = ltn12.sink.table(response)
  }

  return ok, status, table.concat(response)
end

local function getBookList()
  local response = {}

  local ok, status = http.request {
    url = "https://v5jdc5vc-3000.brs.devtunnels.ms/api/koreader/books",
    method = "GET",
    sink = ltn12.sink.table(response)
  }

  if ok and status == 200 then
    local responseBody = table.concat(response)
    local success, books = pcall(json.decode, responseBody)
    if success then
      return books
    else
      logger.err("Error parsing JSON response:", books)
      return nil
    end
  else
    logger.err("HTTP request failed:", status)
    return nil
  end
end

function Readit:init()
  self:onDispatcherRegisterActions()
  self.ui.menu:registerToMainMenu(self)
end

function Readit:showBookList()
  local books = getBookList()

  if not books or #books == 0 then
    UIManager:show(InfoMessage:new {
      text = _("No se pudieron cargar los libros o la lista está vacía"),
    })
    return
  end

  local items = {}
  for _, book in ipairs(books) do
    table.insert(items, {
      text = book.bookInfo,
      callback = function()
        UIManager:show(InfoMessage:new {
          text = "Mandando datos...",
        })
        UIManager:close(self.book_menu)

        local document_path = self.ui.document.file
        local document_hash = util.partialMD5(document_path)
        postJSON({
          googleId = book.googleId,
          hash = document_hash,
        })
      end,
    })
  end

  self.book_menu = Menu:new {
    title = _("Selecciona un libro"),
    item_table = items,
    is_borderless = true,
    is_popout = false,
    width = Screen:getWidth() - 100,
    height = Screen:getHeight() - 100,
  }

  UIManager:show(self.book_menu)
end

function Readit:addToMainMenu(menu_items)
  menu_items.readit = {
    text = _("Read It: Seleccionar libro"),
    -- in which menu this should be appended
    sorting_hint = "more_tools",
    -- a callback when tapping
    callback = function()
      UIManager:show(InfoMessage:new {
        text = _("Cargando libros..."),
      })
      self:showBookList()
    end,
  }
end

return Readit
