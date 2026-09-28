use sea_orm::entity::prelude::*;
use serde::Serialize;

/// {= e.label_plural =} da conta (gerado pelo scaffold a partir do manifest).
#[derive(Clone, Debug, PartialEq, DeriveEntityModel, Serialize)]
#[sea_orm(table_name = "{= e.plural =}")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub id: Uuid,
    /// Dono do registro; nunca sai na API.
    #[serde(skip)]
    pub owner_id: Uuid,
{% for f in e.fields %}
    pub {= f.name =}: {= f.rust =},
{% endfor %}
    pub created_at: DateTimeWithTimeZone,
    pub updated_at: DateTimeWithTimeZone,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
