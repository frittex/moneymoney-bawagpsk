-- The MIT License (MIT)
--
-- Copyright (c) 2012-2016 MRH applications GmbH
-- Copyright (c) Gregor Harlan
-- Copyright (c) 2017 Frittex
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.

WebBanking{
    version = 1.00,
    services    = {"Bawag PSK", "easybank"},
    description = "Bawag PSK / easybank Web-Scraping"
}

-------------------------------------------------------------------------------
-- Config
-------------------------------------------------------------------------------
local debug = false -- if true account and transaction details are printed

-------------------------------------------------------------------------------
-- Member variables
-------------------------------------------------------------------------------
local ignoreSince = false -- ListAccounts sets this to true in order to get
                          -- all transaction in the past

local urlEasybank = "https://ebanking.easybank.at/InternetBanking/InternetBanking?d=login"
local urlBawag = "https://ebanking.bawagpsk.com/InternetBanking/InternetBanking?d=login"

-------------------------------------------------------------------------------
-- Helper functions
-------------------------------------------------------------------------------

-- https://stackoverflow.com/questions/20459943/find-the-last-index-of-a-character-in-a-string
function findLast(haystack, needle)
    local i=haystack:match(".*"..needle.."()")
    if i==nil then return nil else return i-1 end
end

-- A few of these functions were taken and adapted from
-- https://github.com/jgoldhammer/moneymoney-payback

-- remove leading/trailing whitespace from string
local function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function cleanWhitespaces(str) 
    return trim(str:gsub("%s+", " "))
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
    local transactionCodePattern = "((%u%u)/%d%d%d%d%d%d%d%d%d)"
    -- local ibanPattern = "%u%u%d%d%w%w%w%w%w%w%w%w%w%w%w%w?%w?%w?%w?%w?%w?%w?%w?%w?%w?%w?%w?%w?%w?%w?%w?%w?%w?%w?"

    local i, j, transactionCode, shortCode = transactionText:find(transactionCodePattern)

    -- local function hasIBAN()
    --     return transactionText:sub(j+2):match(ibanPattern) ~= nil
    -- end

    -- helper function to extract BIC & IBAN from transactions that contain it
    local function extractBICIBAN(onlyIBAN)
        -- if hasIBAN() then
        local pattern = "^([%wäüö]+)"
        local title = transactionText:sub(j+2)
        local m, n, match = title:find(pattern)
        
        if m ~= nil then
            if onlyIBAN then
                transaction.accountNumber = match
            else
                transaction.bankCode = match
                m, n, match = title:find(pattern, n+2)
                transaction.accountNumber = match
            end

            if n ~= nil then
                transaction.name = title:sub(n+2)
            else
                transaction.name = title
            end
        else
            transaction.name = title
        end
        -- end
    end

    -- BAWAG PSK / easybank uses two-letter codes to denote the type of transaction.
    -- The format of the transaction details is very inconsistent among the transaction types.
    -- This lookup table is therefore used to extract the particular details from every transaction type.
    -- It can be extended, should new transaction codes appear in the future and uses a default for yet unknown types.
    local codeTable = {
        MC = function()
            local timePattern = "(%d%d:%d%d)"
            local m, n = transactionText:find(timePattern)

            transaction.bookingText = "Kartenzahlung"

            if m ~= nil then
                transaction.name = transactionText:sub(n+2)
                transaction.purpose = transactionText:sub(j+2, n)
            else
                transaction.name = transactionText:sub(1, i-1)
                transaction.purpose = transactionText:sub(j+2)
            end
        end;
        BG = function()
            transaction.bookingText = "Konto"
            -- if i == 1 then
            --     transaction.name = transactionText:sub(j+2)
            -- else
            --     transaction.name = transactionText:sub(1, i-1)
            -- end
            transaction.purpose = transactionText:sub(1, i-1)
            extractBICIBAN(false)
        end;
        FE = function()
            transaction.bookingText = "Überweisung"
            transaction.purpose = transactionText:sub(1, i-1)
            extractBICIBAN(true)
        end;
        OG = function()
            transaction.bookingText = "Lastschrift"
            transaction.purpose = transactionText:sub(1, i-1)
            extractBICIBAN(false)
        end;
        VD = function()
            transaction.bookingText = "Überweisung"
            transaction.purpose = transactionText:sub(1, i-1)
            extractBICIBAN(false)
        end;
        VB = function()
            transaction.bookingText = "Überweisung SEPA"
            transaction.purpose = transactionText:sub(1, i-1)
            extractBICIBAN(false)
        end
    }

    -- set default for yet unknown two-letter transaction codes
    local mt = {
        __index = function (t, k)
            return function ()
                transaction.bookingText = "Unbekannt: " .. k
                transaction.name= transactionText
                transaction.purpose = transactionText:sub(1, i-1)
            end
        end
    }
    setmetatable(codeTable, mt)

    codeTable[shortCode]()

    -- clean multi-spaces from fields
    if transaction.purpose ~= nil then
        transaction.purpose = cleanWhitespaces(transaction.purpose)
    end

    if transaction.name ~= nil then
        transaction.name = cleanWhitespaces(transaction.name)
    end

    return transaction
end

-------------------------------------------------------------------------------
-- Scraping
-------------------------------------------------------------------------------

-- global variables to re-use a single connection and cache the entry page of the web banking portal
local connection
local overviewPage


function SupportsBank (protocol, bankCode)
    return protocol == ProtocolWebBanking and (bankCode == "easybank" or bankCode == "Bawag PSK")
end

function InitializeSession (protocol, bankCode, username, username2, password, username3)
    connection = Connection()

    local loginPage = HTML(bankCode == "Bawag PSK" and connection:get(urlBawag) or connection:get(urlEasybank))

    loginPage:xpath("//input[@name='dn']"):attr("value", username)
    loginPage:xpath("//input[@name='pin']"):attr("value", password)

    local loginForm = loginPage:xpath("//form[@name='loginForm']")
    local loginResponsePage = HTML(connection:request(loginForm:submit()))

    local erorrMessage = loginResponsePage:xpath("//*[@id='error_part_text']"):text()
    if string.len(erorrMessage) > 0 then
        MM.printStatus("Login failed. Reason: " .. erorrMessage)
        return "Error received from eBanking: " .. erorrMessage
    end

    overviewPage = loginResponsePage

    MM.printStatus("Login successful");
end

function ListAccounts (knownAccounts)
    ignoreSince = true
    local accounts = {}

    -- navigate to account details
    local navigationForm = overviewPage:xpath("//form[@name='navigationform']")
    navigationForm:xpath("//input[@name='d']"):attr("value", "accountdetails")
    local accountDetailsPage = HTML(connection:request(navigationForm:submit()))

    -- iterate through accounts
    local accountElements = accountDetailsPage:xpath("//select[@name='account_number']/option")
    accountElements:each(function (index, element)

        -- select account
        local accountDetailsForm = accountDetailsPage:xpath("//form[@name='account_details_form']")
        local selectedAccount = accountDetailsForm:xpath("//select[@name='account_number']"):text()
        accountDetailsForm:xpath("//select[@name='account_number']"):select(index - 1)
        accountDetailsPage = HTML(connection:request(accountDetailsForm:submit()))

        -- create account object
        local accountName = accountDetailsPage:xpath("//*[@id='accountDetails']//label[text()='Produktbezeichnung']/../following::div[1]"):text()
        local accountIBAN = accountDetailsPage:xpath("//*[@id='accountDetails']//label[text()='IBAN']/../following::div[1]"):text()
        local accountBIC = accountDetailsPage:xpath("//*[@id='accountDetails']//label[text()='BIC']/../following::div[1]"):text()
        local accountOwner = string.sub(selectedAccount, findLast(selectedAccount, "-") + 2)

        local accountType = AccountTypeOther

        if accountName == "easy gratis" then
            accountType = AccountTypeGiro
        elseif accountName == "easy zinsmax" or accountName == "easy premium" then
            accountType = AccountTypeSavings
        elseif accountName == "easy kreditkarte MasterCard" then
            accountType = AccountTypeCreditCard
        end

        local account = {
            name = accountName,
            accountNumber = accountIBAN,
            bic = accountBIC,
            owner = accountOwner,
            iban = accountIBAN,
            currency = "EUR",
            type = accountType
        }
    
        if debug then
            print("Fetched account:")
            print("  Name:", account.name)
            print("  Number:", account.accountNumber)
            print("  BIC:", account.bic)
            print("  IBAN:", account.iban)
            print("  Currency:", account.currency)
            print("  Type:", account.type)
        end

        table.insert(accounts, account)
    end)

    return accounts
end

function RefreshAccount (account, since)
    -- navigate to transactions
    local navigationForm = overviewPage:xpath("//form[@name='navigationform']")
    navigationForm:xpath("//input[@name='d']"):attr("value", "transactions")
    local transactionsPage = HTML(connection:request(navigationForm:submit()))

    -- select account
    local transactionSearchForm = transactionsPage:xpath("//form[@name='transactionSearchForm']")
    local selectedAccount = transactionSearchForm:xpath("//select[@name='konto']/option[contains(text(), '" .. account.iban .. "')]"):attr("value")
    transactionSearchForm:xpath("//input[@name='accountChange']"):attr("value", "true")
    transactionSearchForm:xpath("//select[@name='konto']"):select(selectedAccount)
    transactionsPage = HTML(connection:request(transactionSearchForm:submit()))

    local balance = transactionsPage:xpath("//form[@name='transactionSearchForm']//div[text()='Kontostand']/../div[2]/span[1]"):text()
    balance = strToAmount(balance)

    -- initiate download of CSV file of all transactions
    local transactionSearchForm = transactionsPage:xpath("//form[@name='transactionSearchForm']")
    transactionSearchForm:xpath("//input[@name='csv']"):attr("value", "true")
    transactionSearchForm:xpath("//input[@name='submitflag']"):attr("value", "true")
    transactionSearchForm:xpath("//input[@name='suppressOverlay']"):attr("value", "true")

    local content, charset, mimeType, filename, headers = connection:request(transactionSearchForm:submit())
    local transactionsCSV = MM.fromEncoding(charset, content)

    -- parse CSV file using an inline callback function to populate the transaction fields
    local transactions = {}
    parseCSV(transactionsCSV, function (fields)
        if #fields < 6 then
            return
        elseif strToDate(fields[4]) ~= nil and (strToDate(fields[4]) >= since or ignoreSince) then
            local transaction = {
                bookingDate = strToDate(fields[4]),
                valueDate   = strToDate(fields[3]),
                amount      = strToAmount(fields[5]),
                currency    = fields[6],
                booked      = true,
            }
            transaction = parseTransaction(fields[2], transaction)

            if debug then
                print("Transaction:")
                print("  Booking Date:", transaction.bookingDate)
                print("  Value Date:", transaction.valueDate)
                print("  Amount:", transaction.amount)
                print("  Currency:", transaction.currency)
                print("  Booking Text:", transaction.bookingText)
                print("  Purpose:", (transaction.purpose and transaction.purpose or "-"))
                print("  Name:", (transaction.name and transaction.name or "-"))
                print("  Bank Code:", (transaction.bankCode and transaction.bankCode or "-"))
                print("  Account Number:", (transaction.accountNumber and transaction.accountNumber or "-"))
            end

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
