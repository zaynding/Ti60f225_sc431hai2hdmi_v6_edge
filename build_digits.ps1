param([string]$Flow='compile')
# Keep the original half-exposure output untouched.
& "$PSScriptRoot/build_shape.ps1" -Flow $Flow -OutputDir 'outflow_digits_5plus2' -WorkDir 'work_digits_5plus2'
if ($LASTEXITCODE) { throw 'Digit-recognition build failed' }
if ($Flow -in @('compile','pgm')) {
    & 'C:/Efinity/2026.1/python311/bin/python.exe' "$PSScriptRoot/tools/report_digit_build.py"
    if ($LASTEXITCODE) { throw 'Digit build report generation failed' }
}
