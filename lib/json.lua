-- Grove Stem Auto-Router / lib/json.lua
-- Recursive-descent JSON parser (zero dependencies)
-- Usage: local JSON = dofile(script_dir .. "lib/json.lua")
--        local val, err = JSON.parse(str)

local M = {}

function M.parse(str)
    if type(str) ~= "string" then
        return nil, "expected string, got " .. type(str)
    end
    local pos = 1

    local function skip_ws()
        while pos <= #str do
            local c = str:byte(pos)
            if c == 32 or c == 9 or c == 10 or c == 13 then
                pos = pos + 1
            else
                break
            end
        end
    end

    local parse_value, parse_object, parse_array
    local parse_string, parse_number

    parse_value = function()
        skip_ws()
        if pos > #str then return nil, "unexpected end of input" end
        local c = str:byte(pos)
        if c == 123 then return parse_object()
        elseif c == 91 then return parse_array()
        elseif c == 34 then return parse_string()
        elseif c == 116 then
            if str:sub(pos, pos + 3) ~= "true" then
                return nil, string.format("unexpected token at %d", pos)
            end; pos = pos + 4; return true
        elseif c == 102 then
            if str:sub(pos, pos + 4) ~= "false" then
                return nil, string.format("unexpected token at %d", pos)
            end; pos = pos + 5; return false
        elseif c == 110 then
            if str:sub(pos, pos + 3) ~= "null" then
                return nil, string.format("unexpected token at %d", pos)
            end; pos = pos + 4; return nil
        elseif c == 45 or (c >= 48 and c <= 57) then
            return parse_number()
        else
            return nil, string.format("unexpected char '%c' at %d", c, pos)
        end
    end

    parse_string = function()
        if str:byte(pos) ~= 34 then
            return nil, string.format("expected '\"' at %d", pos)
        end
        pos = pos + 1
        local parts = {}
        while pos <= #str do
            local c = str:byte(pos)
            if c == 34 then
                pos = pos + 1; return table.concat(parts)
            elseif c == 92 then
                pos = pos + 1
                if pos > #str then return nil, "unterminated escape" end
                local esc = str:byte(pos)
                if esc == 34 then parts[#parts + 1] = '"'
                elseif esc == 92 then parts[#parts + 1] = "\\"
                elseif esc == 47 then parts[#parts + 1] = "/"
                elseif esc == 98 then parts[#parts + 1] = "\b"
                elseif esc == 102 then parts[#parts + 1] = "\f"
                elseif esc == 110 then parts[#parts + 1] = "\n"
                elseif esc == 114 then parts[#parts + 1] = "\r"
                elseif esc == 116 then parts[#parts + 1] = "\t"
                elseif esc == 117 then
                    local hex = str:sub(pos + 1, pos + 4)
                    if #hex < 4 then return nil, "invalid \\u escape" end
                    local code = tonumber(hex, 16)
                    if not code then return nil, "invalid \\u escape" end
                    pos = pos + 4
                    -- Handle surrogate pairs (\uD800-\uDBFF followed by \uDC00-\uDFFF)
                    if code >= 0xD800 and code <= 0xDBFF then
                        local np = pos + 1
                        if str:byte(np) == 92 and str:byte(np + 1) == 117 then
                            local low_hex = str:sub(np + 2, np + 5)
                            if #low_hex == 4 then
                                local low_code = tonumber(low_hex, 16)
                                if low_code and low_code >= 0xDC00 and low_code <= 0xDFFF then
                                    code = 0x10000 + (code - 0xD800) * 0x400 + (low_code - 0xDC00)
                                    pos = np + 5
                                end
                            end
                        end
                    end
                    if code < 0x80 then
                        parts[#parts + 1] = string.char(code)
                    elseif code < 0x800 then
                        parts[#parts + 1] = string.char(0xC0 + math.floor(code / 0x40), 0x80 + (code % 0x40))
                    elseif code < 0x10000 then
                        parts[#parts + 1] = string.char(0xE0 + math.floor(code / 0x1000), 0x80 + (math.floor(code / 0x40) % 0x40), 0x80 + (code % 0x40))
                    else
                        -- 4-byte UTF-8 for codepoints above U+FFFF
                        parts[#parts + 1] = string.char(0xF0 + math.floor(code / 0x40000), 0x80 + (math.floor(code / 0x1000) % 0x40), 0x80 + (math.floor(code / 0x40) % 0x40), 0x80 + (code % 0x40))
                    end
                else
                    return nil, string.format("invalid escape '\\%c' at %d", esc, pos)
                end
                pos = pos + 1
            elseif c < 32 then
                return nil, string.format("invalid control char 0x%02X at %d", c, pos)
            else
                parts[#parts + 1] = string.char(c); pos = pos + 1
            end
        end
        return nil, "unterminated string"
    end

    parse_number = function()
        local start = pos
        if str:byte(pos) == 45 then pos = pos + 1 end
        if pos > #str then return nil, "unexpected end of number" end
        local c = str:byte(pos)
        if c == 48 then pos = pos + 1
        elseif c >= 49 and c <= 57 then
            pos = pos + 1
            while pos <= #str do
                c = str:byte(pos)
                if c >= 48 and c <= 57 then pos = pos + 1 else break end
            end
        else
            return nil, "invalid number at " .. start
        end
        if pos <= #str and str:byte(pos) == 46 then
            pos = pos + 1
            if pos > #str or str:byte(pos) < 48 or str:byte(pos) > 57 then
                return nil, "expected digit after decimal"
            end
            while pos <= #str do
                c = str:byte(pos)
                if c >= 48 and c <= 57 then pos = pos + 1 else break end
            end
        end
        if pos <= #str then
            c = str:byte(pos)
            if c == 69 or c == 101 then
                pos = pos + 1
                if pos <= #str then
                    local s = str:byte(pos)
                    if s == 43 or s == 45 then pos = pos + 1 end
                end
                if pos > #str or str:byte(pos) < 48 or str:byte(pos) > 57 then
                    return nil, "expected digit in exponent"
                end
                while pos <= #str do
                    local d = str:byte(pos)
                    if d >= 48 and d <= 57 then pos = pos + 1 else break end
                end
            end
        end
        local num = tonumber(str:sub(start, pos - 1))
        if not num then return nil, "invalid number at " .. start end
        return num
    end

    parse_object = function()
        pos = pos + 1; local obj = {}; skip_ws()
        if pos <= #str and str:byte(pos) == 125 then pos = pos + 1; return obj end
        local expect_comma = false
        while pos <= #str do
            skip_ws()
            if str:byte(pos) == 125 then pos = pos + 1; return obj end
            if expect_comma then
                if str:byte(pos) ~= 44 then return nil, "expected ',' or '}' at " .. pos end
                pos = pos + 1; skip_ws()
                if str:byte(pos) == 125 then pos = pos + 1; return obj end
            end; expect_comma = true
            if str:byte(pos) ~= 34 then return nil, "expected string key at " .. pos end
            local key, err = parse_string()
            if not key then return nil, err end
            skip_ws()
            if pos > #str or str:byte(pos) ~= 58 then return nil, "expected ':' at " .. pos end
            pos = pos + 1
            local val, err2 = parse_value()
            if err2 then return nil, err2 end
            obj[key] = val
        end
        return nil, "unterminated object"
    end

    parse_array = function()
        pos = pos + 1; local arr = {}; skip_ws()
        if pos <= #str and str:byte(pos) == 93 then pos = pos + 1; return arr end
        local expect_comma = false
        while pos <= #str do
            skip_ws()
            if str:byte(pos) == 93 then pos = pos + 1; return arr end
            if expect_comma then
                if str:byte(pos) ~= 44 then return nil, "expected ',' or ']' at " .. pos end
                pos = pos + 1; skip_ws()
                if str:byte(pos) == 93 then pos = pos + 1; return arr end
            end; expect_comma = true
            local val, err = parse_value()
            if err then return nil, err end
            arr[#arr + 1] = val
        end
        return nil, "unterminated array"
    end

    skip_ws()
    if pos > #str then return nil, "empty input" end
    local result, err = parse_value()
    if err then return nil, err end
    skip_ws()
    if pos <= #str then return nil, string.format("unexpected trailing content at %d", pos) end
    return result
end

function M.stringify(val, pretty)
  local function _serialize(v, visited)
    local t = type(v)
    if t == "nil" then return "null"
    elseif t == "boolean" then return tostring(v)
    elseif t == "number" then
      -- guard against NaN and Inf — invalid in JSON
      if v ~= v or v == math.huge or v == -math.huge then return "null" end
      return tostring(v)
    elseif t == "string" then
      -- backslash FIRST, then quote: http://lua-users.org/wiki/JsonStream
      return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t'):gsub('\f', '\\f') .. '"'
    elseif t == "table" then
      if visited[v] then return "null" end  -- circular reference
      visited[v] = true
      local is_array = true
      local max_idx = 0
      for k in pairs(v) do
        if type(k) ~= "number" or k < 1 then is_array = false; break end
        if k > max_idx then max_idx = k end
      end
      if is_array then
        local parts = {}
        for i = 1, max_idx do
          parts[i] = _serialize(v[i], visited)
        end
        return "[" .. table.concat(parts, ",") .. "]"
      else
        local parts = {}
        for k, val in pairs(v) do
          parts[#parts + 1] = _serialize(k, visited) .. ":" .. _serialize(val, visited)
        end
        return "{" .. table.concat(parts, ",") .. "}"
      end
    else return '"' .. tostring(v) .. '"'
    end
  end
  return _serialize(val, {})
end

return M
