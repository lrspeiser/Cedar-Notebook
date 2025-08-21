use specta::ts::{self, ExportConfiguration};
use specta::Type;

#[derive(Type)]
struct Placeholder;

fn main() {
    // Temporary placeholder export so CI passes until DTOs/routes land.
    let conf = ExportConfiguration::default();
    let out = ts::export::<Placeholder>(&conf).expect("export");
    println!("{}", out);
}
