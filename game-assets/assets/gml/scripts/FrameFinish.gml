function execute_at_end_of_frame() {
    TAXI.depart();
    
    if instance_exists(Game) && Game.go_to_main_menu {
        Game.execute_return_to_menu();
    }
}
