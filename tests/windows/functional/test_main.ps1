function test_Main_no_action {
    $result = Main
    if ($result -eq $STATUS_CODES["scriptFailed"]) { return 0 }
    return 1
}

function test_Main_invalid_action {
    $Action = "Invalid"
    $result = Main
    if ($result -eq $STATUS_CODES["scriptFailed"]) { return 0 }
    return 1
}

function test_Main_failed_dependencies {
    $Action = "Status"
    function Confirm-Dependencies { return $false }
    $result = Main
    if ($result -eq $STATUS_CODES["scriptFailed"]) { return 0 }
    return 1
}

function test_Main_depend {
    $Action = "Depend"
    $result = Main
    if ($result -eq $STATUS_CODES["scriptSuccess"]) { return 0 }
    return 1
}

function test_Main_install_existing_salt {
    $Action = "Install"
    function Find-StandardSaltInstallation { return $true }
    $result = Main
    if ($result -eq $STATUS_CODES["scriptFailed"]) { return 0 }
    return 1
}

function test_Main_install_unknown_status {
    $Action = "Install"
    function Get-Status { return 99 }
    $result = Main
    if ($result -eq $STATUS_CODES["scriptFailed"]) { return 0 }
    return 1
}

function test_Main_install_status_installed {
    $Action = "Install"
    function Get-Status { return $STATUS_CODES["installed"] }
    $result = Main
    if ($result -eq $STATUS_CODES["scriptSuccess"]) { return 0 }
    return 1
}

function test_Main_install_status_installing {
    $Action = "Install"
    function Get-Status { return $STATUS_CODES["installing"] }
    $result = Main
    if ($result -eq $STATUS_CODES["scriptFailed"]) { return 0 }
    return 1
}

function test_Main_install_status_removing {
    $Action = "Install"
    function Get-Status { return $STATUS_CODES["removing"] }
    $result = Main
    if ($result -eq $STATUS_CODES["scriptFailed"]) { return 0 }
    return 1
}

function test_Main_install_success {
    $Action = "Install"
    function Get-Status { return $STATUS_CODES["notInstalled"] }
    function Install {}
    $result = Main
    if ($result -eq $STATUS_CODES["scriptSuccess"]) { return 0 }
    return 1
}

function test_Main_remove_unknown_status {
    $Action = "Remove"
    function Get-Status { return 99 }
    $result = Main
    if ($result -eq $STATUS_CODES["scriptFailed"]) { return 0 }
    return 1
}
function test_Main_remove_status_installing {
    $Action = "Remove"
    function Get-Status { return $STATUS_CODES["installing"] }
    $result = Main
    if ($result -eq $STATUS_CODES["scriptFailed"]) { return 0 }
    return 1
}

function test_Main_remove_status_notInstalled {
    $Action = "Remove"
    function Get-Status { return $STATUS_CODES["notInstalled"] }
    $result = Main
    if ($result -eq $STATUS_CODES["scriptSuccess"]) { return 0 }
    return 1
}
function test_Main_remove_status_removing {
    $Action = "Remove"
    function Get-Status { return $STATUS_CODES["removing"] }
    $result = Main
    if ($result -eq $STATUS_CODES["scriptFailed"]) { return 0 }
    return 1
}
function test_Main_remove_success {
    $Action = "Remove"
    function Get-Status { return $STATUS_CODES["installed"] }
    function Remove {}
    $result = Main
    if ($result -eq $STATUS_CODES["scriptSuccess"]) { return 0 }
    return 1
}

function test_Clear_unknown_status {
    $Action = "Clear"
    function Get-Status { return 99 }
    $result = Main
    if ($result -eq $STATUS_CODES["scriptFailed"]) { return 0 }
    return 1
}
function test_Clear_status_not_installed {
    $Action = "Clear"
    function Get-Status { return $STATUS_CODES["notInstalled"] }
    $result = Main
    if ($result -eq $STATUS_CODES["scriptSuccess"]) { return 0 }
    return 1
}
function test_Clear_success {
    $Action = "Clear"
    function Get-Status { return $STATUS_CODES["installed"] }
    function Reset-SaltMinion {}
    $result = Main
    if ($result -eq $STATUS_CODES["scriptSuccess"]) { return 0 }
    return 1
}

function test_Status_unknown_status {
    $Action = "Status"
    function Get-Status { return 99 }
    $result = Main
    if ($result -eq $STATUS_CODES["scriptFailed"]) { return 0 }
    return 1
}
function test_Status_installed {
    $Action = "Status"
    function Get-Status { return $STATUS_CODES["installed"] }
    $result = Main
    if ($result -eq $STATUS_CODES["installed"]) { return 0 }
    return 1
}
function test_Status_installing {
    $Action = "Status"
    function Get-Status { return $STATUS_CODES["installing"] }
    $result = Main
    if ($result -eq $STATUS_CODES["installing"]) { return 0 }
    return 1
}
function test_Status_notInstalled {
    $Action = "Status"
    function Get-Status { return $STATUS_CODES["notInstalled"] }
    $result = Main
    if ($result -eq $STATUS_CODES["notInstalled"]) { return 0 }
    return 1
}
function test_Status_installFailed {
    $Action = "Status"
    function Get-Status { return $STATUS_CODES["installFailed"] }
    $result = Main
    if ($result -eq $STATUS_CODES["installFailed"]) { return 0 }
    return 1
}
function test_Status_removing {
    $Action = "Status"
    function Get-Status { return $STATUS_CODES["removing"] }
    $result = Main
    if ($result -eq $STATUS_CODES["removing"]) { return 0 }
    return 1
}
function test_Status_removeFailed {
    $Action = "Status"
    function Get-Status { return $STATUS_CODES["removeFailed"] }
    $result = Main
    if ($result -eq $STATUS_CODES["removeFailed"]) { return 0 }
    return 1
}