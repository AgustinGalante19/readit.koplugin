--[[--
@module koplugin.HelloWorld
--]]

local Dispatcher = require("dispatcher") -- luacheck:ignore
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Menu = require("ui/widget/menu")
local InputDialog = require("ui/widget/inputdialog")
local Screen = require("device").screen
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local util = require("util")
local _ = require("gettext")
local json = require("json")
local http = require("socket.http")
local ltn12 = require("ltn12")
local logger = require("logger")
local SQ3 = require("lua-ljsqlite3/init")
local random = require("random")

local debugMode = false

local BASE_API_URL = ""

if not debugMode then
  BASE_API_URL = "https://read-it-blush.vercel.app/api/koreader"
else
  BASE_API_URL = "https://v5jdc5vc-3000.brs.devtunnels.ms/api/koreader"
end


local Readit = WidgetContainer:extend {
  name = "readit",
  is_doc_only = false,
  settings_file = DataStorage:getSettingsDir() .. "/readit.lua",
}

function Readit:onDispatcherRegisterActions()
  Dispatcher:registerAction("readit_action",
    { category = "none", event = "ReadIt", title = _("Read It"), general = true, })
end

function Readit:getUserIdentifier()
  -- Si hay código de usuario configurado, usarlo
  if self.user_code and self.user_code ~= "" then
    return self.user_code
  end

  -- Caso contrario, usar device_id como fallback
  if G_reader_settings:hasNot("device_id") then
    G_reader_settings:saveSetting("device_id", random.uuid())
  end
  return G_reader_settings:readSetting("device_id")
end

function Readit:showUserCodeDialog()
  local input_dialog
  input_dialog = InputDialog:new {
    title = _("Configurar código de usuario"),
    input = self.user_code,
    input_hint = _("Ingresa el código generado desde la app"),
    buttons = {
      {
        {
          text = _("Cancelar"),
          callback = function()
            UIManager:close(input_dialog)
          end,
        },
        {
          text = _("Guardar"),
          is_enter_default = true,
          callback = function()
            local code = input_dialog:getInputText()
            if code and code ~= "" then
              self.user_code = code
              self.settings:saveSetting("user_code", code)
              self.settings:flush()

              UIManager:close(input_dialog)
              UIManager:show(InfoMessage:new {
                text = _("Código guardado exitosamente"),
              })
            else
              UIManager:show(InfoMessage:new {
                text = _("El código no puede estar vacío"),
              })
            end
          end,
        },
      },
    },
  }
  UIManager:show(input_dialog)
  input_dialog:onShowKeyboard()
end

local function postJSON(bodyTable, deviceCode)
  -- Agregar deviceCode al body
  bodyTable.deviceCode = deviceCode

  local body = json.encode(bodyTable)
  local response = {}

  local ok, status = http.request {
    url = BASE_API_URL .. "/hash",
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

local function getBookList(deviceCode)
  local response = {}

  local ok, status = http.request {
    url = BASE_API_URL .. "/books/" .. deviceCode,
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

local function getLastSyncTimestamp(book_hash, deviceCode)
  local response = {}

  local ok, status = http.request {
    url = BASE_API_URL .. "/sync/last/" .. book_hash .. "/" .. deviceCode,
    method = "GET",
    sink = ltn12.sink.table(response)
  }

  if ok and status == 200 then
    local responseBody = table.concat(response)
    local success, data = pcall(json.decode, responseBody)
    if success and data then
      -- Si last_open es null o no existe, retornar 0 (primera sincronización)
      if data.last_open then
        return tonumber(data.last_open)
      else
        return 0
      end
    end
  end

  -- Si hay error de conexión o la API no responde, retornar 0 por defecto
  return 0
end

local function getBookStatistics(book_hash, last_sync_ts)
  local stats_db_path = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
  local conn = SQ3.open(stats_db_path)

  if not conn then
    logger.err("No se pudo abrir statistics.sqlite3")
    return nil
  end

  local book_data = {}
  local reading_sessions = {}

  -- Obtener datos del libro
  local book_query = [[
    SELECT id, title, authors, pages, total_read_time, total_read_pages, last_open
    FROM book
    WHERE md5 = ?
  ]]

  local stmt = conn:prepare(book_query)
  if stmt then
    local result = stmt:reset():bind(book_hash):step()
    if result then
      local book_id = result[1]
      book_data.title = result[2] or ""
      book_data.authors = result[3] or ""
      book_data.pages = tonumber(result[4]) or 0
      book_data.totalReadTime = tonumber(result[5]) or 0
      book_data.totalReadPages = tonumber(result[6]) or 0
      local last_open_timestamp = tonumber(result[7])
      book_data.lastOpen = last_open_timestamp and os.date("!%Y-%m-%dT%H:%M:%SZ", last_open_timestamp) or nil

      -- Obtener solo sesiones nuevas (posteriores a last_sync_ts)
      local sessions_query = [[
        SELECT page, start_time, duration, total_pages
        FROM page_stat_data
        WHERE id_book = ? AND start_time > ?
        ORDER BY start_time ASC
      ]]

      local sessions_stmt = conn:prepare(sessions_query)
      if sessions_stmt then
        sessions_stmt:reset():bind(book_id, last_sync_ts)
        for row in sessions_stmt:rows() do
          table.insert(reading_sessions, {
            page = tonumber(row[1]),
            startTime = os.date("!%Y-%m-%dT%H:%M:%SZ", tonumber(row[2])),
            duration = tonumber(row[3]),
            totalPages = tonumber(row[4])
          })
        end
      end
    end
  end

  conn:close()

  if book_data.title then
    book_data.readingSessions = reading_sessions
    return book_data
  end

  return nil
end

local function syncBookStatistics(book_hash, deviceCode)
  -- Primero obtener el último timestamp sincronizado
  local last_sync_ts = getLastSyncTimestamp(book_hash, deviceCode)

  if not last_sync_ts then
    last_sync_ts = 0 -- Si falla la consulta, usar 0 por defecto
  end

  -- Obtener estadísticas con solo las sesiones nuevas
  local stats = getBookStatistics(book_hash, last_sync_ts)

  if not stats then
    logger.warn("No se encontraron estadísticas para el libro")
    return false
  end

  -- Si no hay sesiones nuevas, no enviar nada (pero actualizar totales)
  if #stats.readingSessions == 0 and last_sync_ts > 0 then
    logger.info("No hay sesiones nuevas para sincronizar")
    return true
  end

  local body = json.encode({
    hash = book_hash,
    deviceCode = deviceCode,
    title = stats.title,
    authors = stats.authors,
    pages = stats.pages,
    totalReadTime = stats.totalReadTime,
    totalReadPages = stats.totalReadPages,
    lastOpen = stats.lastOpen,
    readingSessions = stats.readingSessions
  })

  local response = {}
  local ok, status = http.request {
    url = BASE_API_URL .. "/sync",
    method = "POST",
    headers = {
      ["Content-Type"] = "application/json",
      ["Content-Length"] = #body,
    },
    source = ltn12.source.string(body),
    sink = ltn12.sink.table(response)
  }

  if ok and status == 200 then
    logger.info("Estadísticas sincronizadas exitosamente:", #stats.readingSessions, "sesiones nuevas")
    return true
  else
    logger.err("Error al sincronizar estadísticas:", status)
    return false
  end
end

function Readit:init()
  self:onDispatcherRegisterActions()
  self.ui.menu:registerToMainMenu(self)

  -- Inicializar settings persistentes
  self.settings = LuaSettings:open(self.settings_file)
  self.user_code = self.settings:readSetting("user_code", "")
end

function Readit:onSaveSettings()
  -- Se ejecuta periódicamente y antes de suspensión/cierre
  if self.ui and self.ui.document and self.ui.document.file then
    local document_hash = util.partialMD5(self.ui.document.file)
    local deviceCode = self:getUserIdentifier()
    syncBookStatistics(document_hash, deviceCode)
  end
end

function Readit:onCloseDocument()
  -- Se ejecuta al cerrar el libro explícitamente
  if self.ui and self.ui.document and self.ui.document.file then
    local document_hash = util.partialMD5(self.ui.document.file)
    local deviceCode = self:getUserIdentifier()
    syncBookStatistics(document_hash, deviceCode)
  end
end

function Readit:showBookList()
  local deviceCode = self:getUserIdentifier()
  local books = getBookList(deviceCode)

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
        local deviceCode = self:getUserIdentifier()
        postJSON({
          googleId = book.googleId,
          hash = document_hash,
          pageCount = self.ui.document:getPageCount() or 0
        }, deviceCode)
      end,
    })
  end

  self.book_menu = Menu:new {
    title = _("Selecciona un libro"),
    item_table = items,
    is_borderless = true,
    is_popout = false,
    width = Screen:getWidth(),
    height = Screen:getHeight(),
  }

  UIManager:show(self.book_menu)
end

function Readit:addToMainMenu(menu_items)
  local title = "Read It"
  if debugMode then
    title = title .. " (Debug)"
  end

  -- Obtener el identificador para mostrarlo en el menú
  local deviceCode = self:getUserIdentifier()
  menu_items.readit = {
    text = _(title),
    sub_item_table = {
      {
        text = " ID: " .. deviceCode,
        enabled_func = function() return false end, -- Deshabilitado, solo informativo
      },
      {
        text = _("Configurar código de usuario"),
        callback = function()
          self:showUserCodeDialog()
        end,
      },
      {
        text = _("Seleccionar libro"),
        callback = function()
          UIManager:show(InfoMessage:new {
            text = _("Cargando libros..."),
          })
          self:showBookList()
        end,
      },
      {
        text = _("Sincronizar estadísticas ahora"),
        callback = function()
          if self.ui and self.ui.document and self.ui.document.file then
            UIManager:show(InfoMessage:new {
              text = _("Sincronizando..."),
            })

            local document_hash = util.partialMD5(self.ui.document.file)
            local deviceCode = self:getUserIdentifier()
            local success = syncBookStatistics(document_hash, deviceCode)

            if success then
              UIManager:show(InfoMessage:new {
                text = _("Sincronización exitosa"),
              })
            else
              UIManager:show(InfoMessage:new {
                text = _("Error en la sincronización"),
              })
            end
          else
            UIManager:show(InfoMessage:new {
              text = _("No hay libro abierto"),
            })
          end
        end,
      },
    },
    sorting_hint = "more_tools",
  }
end

return Readit
