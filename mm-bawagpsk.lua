WebBanking{
    version = 0.1,
    url         = "https://ebanking.bawagpsk.com/InternetBanking/InternetBanking?d=login",
    services    = {"Bawag PSK"},
    description = "Bawag PSK Web-Scraping"
}

local connection

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

    MM.printStatus("Login successful");
end

function ListAccounts (knownAccounts)
  -- Return array of accounts.
  local account = {
    name = "Premium Account",
    owner = "Jane Doe",
    accountNumber = "111222333444",
    bankCode = "80007777",
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
  -- Logout.
end