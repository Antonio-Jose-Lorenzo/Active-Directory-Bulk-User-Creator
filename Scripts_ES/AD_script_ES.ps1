Write-Host "*********************************************************************************************"
Write-Host "*********************************************************************************************"
Write-Host "                                                                                            "
Write-Host "                                                                                            "
Write-Host "     .--.                                                                                   "
Write-Host "    |o_o |                                                                                  "
Write-Host "    |:_/ |                                                                                  "
Write-Host "   //   \ \                                                                                 "
Write-Host "  (|     | )                                                                                "
Write-Host "  /'\_   _/`\                                                                               "
Write-Host "  \___)=(___/                                                                               "
Write-Host "   Create by Tec. Antonio J Lorenzo                                                         "
Write-Host "    Linkedin: www.linkedin.com/in/antoniojoselorenzo                                         "
Write-Host "                                                                                            "
Write-Host "*********************************************************************************************"
Write-Host "*********************************************************************************************"
Write-Host "                                                                                            "
Write-Host "                                                                                            "
Write-Host "     Script para crear usuarios de forma masiva en el directorio activo                     "
Write-Host "                                                                                            "
Write-Host "*********************************************************************************************"
Write-Host "*********************************************************************************************"

Import-Module ActiveDirectory -ErrorAction Stop

# Aqui se cargan los modulos del servidor de Active Directory
try {
    $dominio = Get-ADDomain -ErrorAction Stop
    $servidor = $dominio.PDCEmulator

    $unidades = @(
        Get-ADOrganizationalUnit `
            -Filter * `
            -SearchBase $dominio.DistinguishedName `
            -Server $servidor `
            -ErrorAction Stop |
        Sort-Object DistinguishedName
    )
}
catch {
    throw "No se pudo consultar Active Directory: $($_.Exception.Message)"
}

if ($unidades.Count -eq 0) {
    throw "No se encontraron unidades organizativas en el dominio."
}

# Aqui mostramos todas las unidades organizativas disponibles
Write-Host "UNIDADES ORGANIZATIVAS DISPONIBLES" -ForegroundColor Cyan

for ($i = 0; $i -lt $unidades.Count; $i++) {
    Write-Host ("[{0}] {1}" -f ($i + 1), $unidades[$i].DistinguishedName)
}

# Es necesario elegir la unidad donde se cargaran los usuarios.
do {
    $entrada = Read-Host "Seleccione el número de la OU de destino"
    $seleccion = 0

    $valida = [int]::TryParse($entrada, [ref]$seleccion)

    if (
        -not $valida -or
        $seleccion -lt 1 -or
        $seleccion -gt $unidades.Count
    ) {
        Write-Host "Seleccione un número válido de la lista." -ForegroundColor Yellow
        $valida = $false
    }
}
until ($valida)

$ouDestino = $unidades[$seleccion - 1].DistinguishedName

Write-Host "`nOU seleccionada: $ouDestino" -ForegroundColor Green

# Solicitar e importar el archivo CSV.
$ruta = (Read-Host "Ingrese la ruta del archivo CSV").Trim().Trim('"')
# por Defecto, la ruta seria ejemplo: C/User/tu usuario/desktop/archivo.csv 
if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) {
    throw "No se encontró el archivo CSV: $ruta"
}

# Cambia ',' por ';' si ese es el separador de tu archivo.
$usuarios = @(
    Import-Csv -LiteralPath $ruta -Delimiter ',' -Encoding UTF8 -ErrorAction Stop
)

if ($usuarios.Count -eq 0) {
    throw "El archivo CSV no contiene usuarios."
}

# Validar las columnas obligatorias.
$columnas = $usuarios[0].PSObject.Properties.Name

foreach ($columna in @('Cuenta', 'Nombre', 'Clave')) {
    if ($columna -notin $columnas) {
        throw "Falta la columna obligatoria '$columna'. Comprueba también el separador del CSV."
    }
}

$creados = 0
$omitidos = 0
$fallidos = 0

$camposOpcionales = @{
    GivenName    = 'Nombres'
    Surname      = 'Apellidos'
    Description  = 'Descripcion'
    Office       = 'Oficina'
    OfficePhone  = 'Telefono'
    EmailAddress = 'Email'
    Title        = 'Titulo'
    Department   = 'Departamento'
    Company      = 'Compania'
    City         = 'Ciudad'
    State        = 'Estado'
}

foreach ($usuario in $usuarios) {
    $cuenta = ([string]$usuario.Cuenta).Trim()

    try {
        if ([string]::IsNullOrWhiteSpace($cuenta)) {
            throw "La columna Cuenta está vacía."
        }

        if ([string]::IsNullOrWhiteSpace($usuario.Nombre)) {
            throw "La columna Nombre está vacía."
        }

        if ([string]::IsNullOrWhiteSpace($usuario.Clave)) {
            throw "La columna Clave está vacía."
        }

        # Comprobar si la cuenta ya existe en el dominio.
        $cuentaFiltro = $cuenta.Replace("'", "''")

        $existente = Get-ADUser `
            -Filter "SamAccountName -eq '$cuentaFiltro'" `
            -Server $servidor `
            -ErrorAction Stop

        if ($existente) {
            Write-Host "Omitido: $cuenta ya existe." -ForegroundColor Yellow
            $omitidos++
            continue
        }

        $parametros = @{
            SamAccountName        = $cuenta
            UserPrincipalName     = "$cuenta@$($dominio.DNSRoot)"
            Name                  = $usuario.Nombre.Trim()
            DisplayName           = $usuario.Nombre.Trim()
            AccountPassword       = ConvertTo-SecureString `
                                        $usuario.Clave -AsPlainText -Force
            Path                  = $ouDestino
            Server                = $servidor
            Enabled               = $true
            ChangePasswordAtLogon = $true
            ErrorAction           = 'Stop'
        }

        foreach ($campo in $camposOpcionales.GetEnumerator()) {
            $valor = [string]$usuario.($campo.Value)

            if (-not [string]::IsNullOrWhiteSpace($valor)) {
                $parametros[$campo.Key] = $valor.Trim()
            }
        }

        New-ADUser @parametros

        Write-Host "Creado: $cuenta" -ForegroundColor Green
        $creados++
    }
    catch {
        Write-Warning "Error con '$cuenta': $($_.Exception.Message)"
        $fallidos++
    }
}

Write-Host "`nProceso finalizado." -ForegroundColor Cyan
Write-Host "OU de destino: $ouDestino"
Write-Host "Creados: $creados | Omitidos: $omitidos | Con errores: $fallidos"
Write-Host "`nProceso finalizado. Cierre esta ventana con la X para salir." -ForegroundColor Cyan

while ($true) {
    Start-Sleep -Seconds 1
}