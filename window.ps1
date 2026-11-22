Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds

$bitmap = New-Object System.Drawing.Bitmap(
    $bounds.Width,
    $bounds.Height
)

$graphics = [System.Drawing.Graphics]::FromImage($bitmap)

$graphics.CopyFromScreen(
    $bounds.Location,
    [System.Drawing.Point]::Empty,
    $bounds.Size
)

$graphics.Dispose()

$form = New-Object System.Windows.Forms.Form
$form.Text = "My PowerShell Window"
$form.Size = New-Object System.Drawing.Size(800, 600)
$form.StartPosition = "CenterScreen"

$pictureBox = New-Object System.Windows.Forms.PictureBox
$pictureBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$pictureBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$pictureBox.Image = $bitmap

$form.Controls.Add($pictureBox)

$form.Add_FormClosed({
    $pictureBox.Image.Dispose()
})

$form.ShowDialog()