pub mod types;

use rspc::Router;

#[derive(Clone)]
pub struct Ctx;
impl Ctx { pub fn new() -> Self { Ctx } }

pub fn build_router() -> Router<Ctx> {
    Router::new().build()
}
