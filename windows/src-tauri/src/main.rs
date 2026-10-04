// mati-notch runs without a console window: mati-notch is the whole UI.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    mati_notch_lib::run()
}
