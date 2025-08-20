pub mod types;

use rspc::Router;

#[derive(Clone)]
pub struct Ctx;
impl Ctx { pub fn new() -> Self { Ctx } }

pub fn build_router() -> Router<Ctx> {
    Router::new()
        .query("list_runs", |t| t(|_ctx: Ctx, limit: Option<u32>| -> Result<Vec<types::RunSummary>, rspc::Error> {
            let limit = limit.unwrap_or(20) as usize;
            let runs = notebook_core::runs::list_runs(limit).map_err(|e| rspc::Error::new(rspc::ErrorCode::InternalServerError, e.to_string()))?;
            let out: Vec<types::RunSummary> = runs.into_iter().map(|r| types::RunSummary{ id: r.id, path: r.dir.to_string_lossy().into() }).collect();
            Ok(out)
        }))
        .mutation("run_julia", |t| t(|_ctx: Ctx, code: String| -> Result<types::RunAck, rspc::Error> {
            let run = notebook_core::runs::create_new_run(None).map_err(|e| rspc::Error::new(rspc::ErrorCode::InternalServerError, e.to_string()))?;
            let out = notebook_core::executors::julia::run_julia_cell(&run.dir, &code).map_err(|e| rspc::Error::new(rspc::ErrorCode::InternalServerError, e.to_string()))?;
            Ok(types::RunAck{ run_id: run.id, ok: out.ok, message: Some(out.message) })
        }))
        .mutation("run_shell", |t| t(|_ctx: Ctx, (cmd, cwd, timeout_secs): (String, Option<String>, Option<u64>)| -> Result<types::RunAck, rspc::Error> {
            let run = notebook_core::runs::create_new_run(None).map_err(|e| rspc::Error::new(rspc::ErrorCode::InternalServerError, e.to_string()))?;
            let out = notebook_core::executors::shell::run_shell(&run.dir, &cmd, cwd.as_deref(), timeout_secs).map_err(|e| rspc::Error::new(rspc::ErrorCode::InternalServerError, e.to_string()))?;
            Ok(types::RunAck{ run_id: run.id, ok: out.ok, message: Some(out.message) })
        }))
        .build()
}
