pub mod types;

use rspc::{Error, ErrorCode, Router};
use serde::Deserialize;
use specta::Type;
use std::sync::Arc;

#[derive(Clone)]
pub struct Ctx;
impl Ctx { pub fn new() -> Self { Ctx } }

#[derive(Deserialize, Type)]
pub struct ListRunsArgs { pub limit: Option<u32> }

#[derive(Deserialize, Type)]
pub struct RunJuliaArgs { pub code: String }

#[derive(Deserialize, Type)]
pub struct RunShellArgs {
    pub cmd: String,
    pub cwd: Option<String>,
    pub timeout_secs: Option<u64>,
}

fn internal<E: std::fmt::Display>(e: E) -> Error {
    Error::new(ErrorCode::InternalServerError, e.to_string())
}

pub fn build_router() -> Arc<Router<Ctx>> {
    Router::new()
        .query("list_runs", |t| t(|_ctx, args: ListRunsArgs| async move {
            let limit = args.limit.unwrap_or(20) as usize;
            let runs = notebook_core::runs::list_runs(limit).map_err(internal)?;
            Ok(runs.into_iter().map(|r| types::RunSummary {
                id: r.id,
                path: r.dir.to_string_lossy().into()
            }).collect::<Vec<_>>())
        }))
        .mutation("run_julia", |t| t(|_ctx, args: RunJuliaArgs| async move {
            let run = notebook_core::runs::create_new_run(None).map_err(internal)?;
            let out  = notebook_core::executors::julia::run_julia_cell(&run.dir, &args.code)
                .map_err(internal)?;
            Ok(types::RunAck { run_id: run.id, ok: out.ok, message: Some(out.message) })
        }))
        .mutation("run_shell", |t| t(|_ctx, args: RunShellArgs| async move {
            let run = notebook_core::runs::create_new_run(None).map_err(internal)?;
            let out  = notebook_core::executors::shell::run_shell(
                &run.dir, &args.cmd, args.cwd.as_deref(), args.timeout_secs
            ).map_err(internal)?;
            Ok(types::RunAck { run_id: run.id, ok: out.ok, message: Some(out.message) })
        }))
        .build()
        .arced()
}
