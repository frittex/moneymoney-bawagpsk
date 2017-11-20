WebBanking{
    version = 0.1,
    url         = "https://ebanking.bawagpsk.com/InternetBanking/InternetBanking?d=login",
    services    = {"Bawag PSK"},
    description = "Bawag PSK Web-Scraping"
}

-------------------------------------------------------------------------------
-- Helper functions
-------------------------------------------------------------------------------
-- A few of these functions were taken and adapted from
-- https://github.com/jgoldhammer/moneymoney-payback

-- remove leading/trailing whitespace from string
local function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- convert German localized amount string to number object
local function strToAmount(str)
    str = string.gsub(str, "[^-,%d]", "")
    str = string.gsub(str, ",", ".")
    return tonumber(str)
end

-- convert German localized date string to date object
local function strToDate(str)
    local d, m, y = string.match(str, "(%d%d).(%d%d).(%d%d%d%d)")
    if d and m and y then
        return os.time { year = y, month = m, day = d, hour = 0, min = 0, sec = 0 }
    end
end

-- makeshift function to parse a CSV string
-- calls rowCallback(cols) on every row, passing a table of all extracted fields
-- taken from https://github.com/gharlan/moneymoney-shoop
local function parseCSV (csv, rowCallback)
    csv = csv .. "\n"
    local len    = string.len(csv)
    local cols   = {}
    local field  = ""
    local quoted = false
    local start  = false

    local i = 1
    while i <= len do
        local c = string.sub(csv, i, i)
        if quoted then
            if c == '"' then
                if i + 1 <= len and string.sub(csv, i + 1, i + 1) == '"' then
                    -- Escaped quotation mark.
                    field = field .. c
                    i = i + 1
                else
                    -- End of quotaton.
                    quoted = false
                end
            else
                field = field .. c
            end
        else
            if start and c == '"' then
                -- Begin of quotation.
                quoted = true
            elseif c == ";" then
                -- Field separator.
                table.insert(cols, field)
                field  = ""
                start  = true
            elseif c == "\r" then
                -- Ignore carriage return.
            elseif c == "\n" then
                -- New line. Call callback function.
                table.insert(cols, field)
                rowCallback(cols)
                cols   = {}
                field  = ""
                quoted = false
                start  = true
            else
                field = field .. c
            end
        end
        i = i + 1
    end
end

-------------------------------------------------------------------------------
-- Parsing
-------------------------------------------------------------------------------

-- function to parse transaction details from CSV fields
local function parseTransaction(transactionText, transaction)
    local transactionCodePattern = "((%a%a)/%d%d%d%d%d%d%d%d%d)"
    local i, j, transactionCode, shortCode = transactionText:find(transactionCodePattern)

    local function extractBICIBAN(onlyIBAN)
        local pattern = "^(%w+)"
        local title = transactionText:sub(j+2)
        local m, n, match = title:find(pattern)
        if onlyIBAN then
            transaction.accountNumber = match
        else
            transaction.bankCode = match
            m, n, match = title:find(pattern, n+2)
            transaction.accountNumber = match
        end
        transaction.name = title:sub(n+2)
    end

    local codeTable = {
        MC = function()
            local timePattern = "(%d%d:%d%d)"
            local m, n = transactionText:find(timePattern)

            transaction.bookingText = "Kartenzahlung"
            transaction.name = transactionText:sub(n+2)
            transaction.purpose = transactionText:sub(j+2, n)
        end;
        BG = function()
            transaction.bookingText = "Konto"
            if i == 1 then
                transaction.name = trim(transactionText:sub(j+2))
            else
                transaction.name = trim(transactionText:sub(1, i-1))
            end
        end;
        FE = function()
            transaction.bookingText = "Überweisung"
            extractBICIBAN(true)
        end;
        OG = function()
            transaction.bookingText = "Lastschrift"
            transaction.purpose = trim(transactionText:sub(1, i-1))
            extractBICIBAN(false)
        end;
        VD = function()
            transaction.bookingText = "Eingehende Überweisung"
            transaction.purpose= trim(transactionText:sub(1, i-1))
            extractBICIBAN(false)
        end;
        VB = function()
            transaction.bookingText = "Überweisung SEPA"
            transaction.purpose= trim(transactionText:sub(1, i-1))
            extractBICIBAN(false)
        end
    }

    codeTable[shortCode]()
    return transaction
end

-------------------------------------------------------------------------------
-- Scraping
-------------------------------------------------------------------------------

local connection
local overviewPage

function SupportsBank (protocol, bankCode)
    return protocol == ProtocolWebBanking and bankCode == "Bawag PSK"
end

function InitializeSession (protocol, bankCode, username, username2, password, username3)
    connection = Connection()

    local loginPage = HTML(connection:get(url))

    loginPage:xpath("//input[@name='dn']"):attr("value", username)
    loginPage:xpath("//input[@name='pin']"):attr("value", password)

    local loginForm = loginPage:xpath("//form[@name='loginForm']")
    local loginResponsePage = HTML(connection:request(loginForm:submit()))

    local erorrMessage = loginResponsePage:xpath("//*[@id='error_part_text']"):text()
    if string.len(erorrMessage) > 0 then
        MM.printStatus("Login failed. Reason: " .. erorrMessage)
        -- return LoginFailed
        return "Error received from BAWAG eBanking: " .. erorrMessage
    end

    overviewPage = loginResponsePage

    MM.printStatus("Login successful");
end

function ListAccounts (knownAccounts)
    local navigationForm = overviewPage:xpath("//form[@name='navigationform']")
    navigationForm:xpath("//input[@name='d']"):attr("value", "accountdetails")
    local accountDetailsPage = HTML(connection:request(navigationForm:submit()))

    local accountName = accountDetailsPage:xpath("//label[text()='Produktbezeichnung']/following::label[1]"):text()
    local accountIBAN = accountDetailsPage:xpath("//label[text()='IBAN']/following::label[1]"):text()
    local accountBIC = accountDetailsPage:xpath("//label[text()='BIC']/following::label[1]"):text()
    local accountOwner = accountDetailsPage:xpath("//label[text()='Name']/following::label[1]"):text()

    -- Return array of accounts.
    local account = {
        name = accountName,
        accountNumber = accountIBAN,
        bic = accountBIC,
        owner = accountOwner,
        iban = accountIBAN,
        currency = "EUR",
        type = AccountTypeGiro
    }
    return {account}
end

function RefreshAccount (account, since)
    local navigationForm = overviewPage:xpath("//form[@name='navigationform']")
    navigationForm:xpath("//input[@name='d']"):attr("value", "transactions")
    local transactionsPage = HTML(connection:request(navigationForm:submit()))

    local balance = transactionsPage:xpath("//span[@class='konto-stand-sum']/span[1]"):text()
    balance = strToAmount(balance)

    local transactionSearchForm = transactionsPage:xpath("//form[@name='transactionSearchForm']")
    transactionSearchForm:xpath("//input[@name='csv']"):attr("value", "true")
    transactionSearchForm:xpath("//input[@name='submitflag']"):attr("value", "true")
    transactionSearchForm:xpath("//input[@name='suppressOverlay']"):attr("value", "true")

    local content, charset, mimeType, filename, headers = connection:request(transactionSearchForm:submit())
    local transactionsCSV = MM.fromEncoding(charset, content)

    local transactions = {}
    parseCSV(transactionsCSV, function (fields)
        if #fields < 6 then
            return
        elseif strToDate(fields[4]) ~= nil and strToDate(fields[4]) >= since then
            local transaction = {
                bookingDate = strToDate(fields[4]),
                valueDate   = strToDate(fields[3]),
                amount      = strToAmount(fields[5]),
                currency    = "EUR",
                booked      = true,
            }
            transaction = parseTransaction(fields[2], transaction)
            table.insert(transactions, transaction)
        end
    end)

    return {balance=balance, transactions=transactions}
end

function EndSession ()
    local navigationForm = overviewPage:xpath("//form[@name='navigationform']")
    navigationForm:xpath("//input[@name='d']"):attr("value", "logoutredirect")
    local transactionsPage = HTML(connection:request(navigationForm:submit()))
end
