<?php
    $con=mysqli_connect("127.0.0.1","root","newhand","test");
    if(!$con){
        die('失败');
                    
    }
   // $db_selected = mysql_select_db("test",$con);
    $sql="select rand_string(10) my from dual";

    $res=mysqli_query($con,$sql);
    
    if($row=mysqli_fetch_assoc($res)){
            
        echo $row['my'];
    }
        

