WebBanking{
    version = 0.1,
    url         = "https://ebanking.bawagpsk.com/InternetBanking/InternetBanking?d=login",
    services    = {"Bawag PSK"},
    description = "Bawag PSK Web-Scraping"
}

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
  -- Return balance and array of transactions.
  local transaction = {
    bookingDate = 1325764800,
    purpose = "Hello World!",
    amount = 42.00
  }
  return {balance=42.00, transactions={transaction}}
end

function EndSession ()
    local navigationForm = overviewPage:xpath("//form[@name='navigationform']")
    navigationForm:xpath("//input[@name='d']"):attr("value", "logoutredirect")
    local transactionsPage = HTML(connection:request(navigationForm:submit()))
end
