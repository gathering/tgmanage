<?php    
    if(isset($_GET['mode'])){
        if($_GET['mode'] === 'config'){
            # LASTE NED CONFIG
            /*
            header('Content-Description: File Transfer');
            header('Content-Type: application/octet-stream');
            header('Content-Disposition: attachment; filename='.basename($file));
            header('Content-Length: ' . filesize('../files/' . $_GET['file']));
            
            
            */

            $dbconn = pg_connect("host=localhost dbname=bootstrap user=bootstrap password=asdf")
                or die('Could not connect: ' . pg_last_error());

            // Performing SQL query
            $query = 'SELECT * FROM switches WHERE hostname = \'' . $_GET['hostname'] . '\'';
            $result = pg_query($query) or die('Query failed: ' . pg_last_error());
            if(pg_num_rows($result) == 1){
                $c = pg_fetch_assoc($result);
                include 'ex2200.template';
            }else{
                header("HTTP/1.0 404 Not Found");
                die();
            }
            
        }elseif($_GET['mode'] === 'image'){
            if(isset($_GET['file']) && is_readable('../files/' . $_GET['file'])){
                # SEND IMAGE
                header('Content-Description: File Transfer');
                header('Content-Type: application/octet-stream');
                header('Content-Disposition: attachment; filename='.basename($file));
                header('Content-Length: ' . filesize('../files/' . $_GET['file']));
                readfile('../files/' . $_GET['file']);
            }else{
                header("HTTP/1.1 404 Not Found");
                die();
            }

        }
    }
    /*
    if(substr($_SERVER['REQUEST_URI'], 0, 7 === '/files/'){
        # Laste ned JunOS-fil
        echo 'henter fil';
    }elseif(substr($_SERVER['REQUEST_URI'], 0, 9 === '/tg-edge/'){
        # Hente config fra Postgres
        echo 'henter config';
    }
    */
?>
