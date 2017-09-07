<?php
    $link_id=mysqli_connect('127.0.0.1','root','newhand');
    if($link_id){
        echo "mysql successful";
    }else{
        echo "mysql_error()";
    }
?>

