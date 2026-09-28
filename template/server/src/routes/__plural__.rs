//! {= e.label_plural =} da conta, sobre o query builder do SeaORM. Toda consulta filtra pelo dono:
//! registro alheio responde 404, igual ao inexistente.

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use chrono::Utc;
use sea_orm::{ActiveModelTrait, ColumnTrait, DatabaseConnection, EntityTrait, QueryFilter, QueryOrder, Set};
use serde::Deserialize;
use uuid::Uuid;

#[allow(unused_imports)]
use super::err;
use super::{ApiError, ApiResult};
use crate::{
    auth::Auth,
    entities::{prelude::{= e.class =}, {= e.name =}},
};

async fn owned(db: &DatabaseConnection, auth: &Auth, id: Uuid) -> Result<{= e.name =}::Model, ApiError> {
    {= e.class =}::find_by_id(id).filter({= e.name =}::Column::OwnerId.eq(auth.user_id)).one(db).await?.ok_or_else(ApiError::not_found)
}
{% for f in e.fields %}

/// {= f.label =}: {% if f.kind in ["string", "text"] %}texto{% if f.required %} obrigatório{% endif %}{% if f.max is not none %}, até {= f.max =} caracteres{% endif %}{% elif f.kind == "bool" %}sim ou não{% else %}número{% if f.min is not none %}, a partir de {= f.min =}{% endif %}{% if f.max is not none %}, até {= f.max =}{% endif %}{% endif %}.
{% if f.kind in ["string", "text"] %}
fn check_{= f.name =}(raw: String) -> Result<String, ApiError> {
    let v = raw.trim();
{% if f.required %}
    if v.is_empty() {
        return Err(err(StatusCode::BAD_REQUEST, "{= f.label_lower =}: obrigatório"));
    }
{% endif %}
{% if f.max is not none %}
    if v.chars().count() > {= f.max =} {
        return Err(err(StatusCode::BAD_REQUEST, "{= f.label_lower =}: até {= f.max =} caracteres"));
    }
{% endif %}
{% if f.kind == "string" %}
    if v.chars().any(char::is_control) {
        return Err(err(StatusCode::BAD_REQUEST, "{= f.label_lower =}: sem quebra de linha"));
    }
{% endif %}
    Ok(v.to_string())
}
{% elif f.kind == "bool" %}
const fn check_{= f.name =}(v: bool) -> Result<bool, ApiError> {
    Ok(v)
}
{% else %}
fn check_{= f.name =}(v: {= f.rust =}) -> Result<{= f.rust =}, ApiError> {
{% if f.kind == "float" %}
    if !v.is_finite() {
        return Err(err(StatusCode::BAD_REQUEST, "{= f.label_lower =}: número inválido"));
    }
{% endif %}
{% if f.min is not none %}
    if v < {= f.min_lit =} {
        return Err(err(StatusCode::BAD_REQUEST, "{= f.label_lower =}: no mínimo {= f.min =}"));
    }
{% endif %}
{% if f.max is not none %}
    if v > {= f.max_lit =} {
        return Err(err(StatusCode::BAD_REQUEST, "{= f.label_lower =}: no máximo {= f.max =}"));
    }
{% endif %}
    Ok(v)
}
{% endif %}
{% endfor %}

pub async fn list(State(db): State<DatabaseConnection>, auth: Auth) -> ApiResult<Vec<{= e.name =}::Model>> {
    let rows = {= e.class =}::find().filter({= e.name =}::Column::OwnerId.eq(auth.user_id)).order_by_desc({= e.name =}::Column::UpdatedAt).all(&db).await?;
    Ok(Json(rows))
}

pub async fn get(State(db): State<DatabaseConnection>, auth: Auth, Path(id): Path<Uuid>) -> ApiResult<{= e.name =}::Model> {
    Ok(Json(owned(&db, &auth, id).await?))
}

#[derive(Deserialize)]
pub struct New{= e.class =} {
{% for f in e.fields %}
    {= f.name =}: Option<{= f.rust =}>,
{% endfor %}
}

pub async fn create(State(db): State<DatabaseConnection>, auth: Auth, Json(b): Json<New{= e.class =}>) -> Result<(StatusCode, Json<{= e.name =}::Model>), ApiError> {
    let now = Utc::now().fixed_offset();
    let row = {= e.name =}::ActiveModel {
        id: Set(Uuid::new_v4()),
        owner_id: Set(auth.user_id),
{% for f in e.fields %}
{% if f.default_rust == "String::new()" %}
        {= f.name =}: Set(check_{= f.name =}(b.{= f.name =}.unwrap_or_default())?),
{% elif f.kind in ["string", "text"] %}
        {= f.name =}: Set(check_{= f.name =}(b.{= f.name =}.unwrap_or_else(|| {= f.default_rust =}))?),
{% else %}
        {= f.name =}: Set(check_{= f.name =}(b.{= f.name =}.unwrap_or({= f.default_rust =}))?),
{% endif %}
{% endfor %}
        created_at: Set(now),
        updated_at: Set(now),
    }
    .insert(&db)
    .await?;
    Ok((StatusCode::CREATED, Json(row)))
}

#[derive(Deserialize)]
pub struct Patch{= e.class =} {
{% for f in e.fields %}
    {= f.name =}: Option<{= f.rust =}>,
{% endfor %}
}

pub async fn patch(State(db): State<DatabaseConnection>, auth: Auth, Path(id): Path<Uuid>, Json(b): Json<Patch{= e.class =}>) -> ApiResult<{= e.name =}::Model> {
    let mut row: {= e.name =}::ActiveModel = owned(&db, &auth, id).await?.into();
{% for f in e.fields %}
    if let Some(v) = b.{= f.name =} {
        row.{= f.name =} = Set(check_{= f.name =}(v)?);
    }
{% endfor %}
    row.updated_at = Set(Utc::now().fixed_offset());
    Ok(Json(row.update(&db).await?))
}

pub async fn delete(State(db): State<DatabaseConnection>, auth: Auth, Path(id): Path<Uuid>) -> Result<StatusCode, ApiError> {
    let r = {= e.class =}::delete_many().filter({= e.name =}::Column::Id.eq(id)).filter({= e.name =}::Column::OwnerId.eq(auth.user_id)).exec(&db).await?;
    if r.rows_affected == 0 {
        return Err(ApiError::not_found());
    }
    Ok(StatusCode::NO_CONTENT)
}
