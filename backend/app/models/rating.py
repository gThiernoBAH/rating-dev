# 2026-10-02 — modèles ORM (miroir strict de scripts/schema.sql §12).
from datetime import date, datetime

from sqlalchemy import (
    Boolean, CheckConstraint, Date, DateTime, ForeignKey, Integer,
    Numeric, SmallInteger, Text, UniqueConstraint, VARCHAR, JSON,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class Site(Base):
    __tablename__ = "sites"
    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(VARCHAR(20), unique=True)
    libelle: Mapped[str] = mapped_column(VARCHAR(120))


class Departement(Base):
    __tablename__ = "departements"
    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(VARCHAR(20), unique=True)
    libelle: Mapped[str] = mapped_column(VARCHAR(120))
    site_id: Mapped[int] = mapped_column(ForeignKey("sites.id"))


class Section(Base):
    __tablename__ = "sections"
    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(VARCHAR(20), unique=True)
    libelle: Mapped[str] = mapped_column(VARCHAR(120))
    departement_id: Mapped[int] = mapped_column(ForeignKey("departements.id"))


class Emploi(Base):
    __tablename__ = "emplois"
    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(VARCHAR(20), unique=True)
    libelle: Mapped[str] = mapped_column(VARCHAR(120))
    famille: Mapped[int] = mapped_column(SmallInteger)  # 1 Cadres / 2 AM / 3 Empl.-Ouvr.


class Categorie(Base):
    __tablename__ = "categories"
    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(VARCHAR(20), unique=True)
    libelle: Mapped[str] = mapped_column(VARCHAR(120))


class Poste(Base):
    __tablename__ = "postes"
    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(VARCHAR(20), unique=True)
    libelle: Mapped[str] = mapped_column(VARCHAR(120))


class Critere(Base):
    __tablename__ = "criteres"
    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(VARCHAR(20), unique=True)
    libelle: Mapped[str] = mapped_column(VARCHAR(200))
    actif: Mapped[bool] = mapped_column(Boolean, default=True)
    details: Mapped[list["CritereDetail"]] = relationship(
        back_populates="critere", cascade="all, delete-orphan"
    )


class CritereDetail(Base):
    __tablename__ = "critere_details"
    id: Mapped[int] = mapped_column(primary_key=True)
    critere_id: Mapped[int] = mapped_column(ForeignKey("criteres.id"))
    libelle_descriptif: Mapped[str] = mapped_column(VARCHAR(300))
    valeur: Mapped[float] = mapped_column(Numeric(5, 2))
    ordre: Mapped[int] = mapped_column(Integer, default=0)
    critere: Mapped[Critere] = relationship(back_populates="details")


class Profil(Base):
    __tablename__ = "profils"
    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(VARCHAR(20), unique=True)
    libelle: Mapped[str] = mapped_column(VARCHAR(120))


class ProfilCritere(Base):
    __tablename__ = "profil_criteres"
    id: Mapped[int] = mapped_column(primary_key=True)
    profil_id: Mapped[int] = mapped_column(ForeignKey("profils.id"))
    critere_id: Mapped[int] = mapped_column(ForeignKey("criteres.id"))
    coefficient: Mapped[float] = mapped_column(Numeric(5, 2))
    ordre: Mapped[int] = mapped_column(Integer, default=0)
    __table_args__ = (UniqueConstraint("profil_id", "critere_id"),)


class EmploiProfil(Base):
    __tablename__ = "emploi_profils"
    id: Mapped[int] = mapped_column(primary_key=True)
    emploi_id: Mapped[int] = mapped_column(ForeignKey("emplois.id"))
    profil_id: Mapped[int] = mapped_column(ForeignKey("profils.id"))
    ordre: Mapped[int] = mapped_column(Integer, default=0)
    __table_args__ = (UniqueConstraint("emploi_id", "profil_id"),)


class Salarie(Base):
    __tablename__ = "salaries"
    id: Mapped[int] = mapped_column(primary_key=True)
    matricule: Mapped[str] = mapped_column(VARCHAR(20), unique=True)
    nom: Mapped[str] = mapped_column(VARCHAR(120))
    prenoms: Mapped[str | None] = mapped_column(VARCHAR(120), nullable=True)
    site_id: Mapped[int | None] = mapped_column(ForeignKey("sites.id"), nullable=True)
    departement_id: Mapped[int | None] = mapped_column(ForeignKey("departements.id"), nullable=True)
    section_id: Mapped[int | None] = mapped_column(ForeignKey("sections.id"), nullable=True)
    emploi_id: Mapped[int | None] = mapped_column(ForeignKey("emplois.id"), nullable=True)
    categorie_id: Mapped[int | None] = mapped_column(ForeignKey("categories.id"), nullable=True)
    poste_id: Mapped[int | None] = mapped_column(ForeignKey("postes.id"), nullable=True)
    date_embauche: Mapped[date | None] = mapped_column(Date, nullable=True)
    email: Mapped[str | None] = mapped_column(VARCHAR(200), nullable=True)
    n1_id: Mapped[int | None] = mapped_column(ForeignKey("salaries.id"), nullable=True)
    hors_evaluation: Mapped[bool] = mapped_column(Boolean, default=False)
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    must_change_password: Mapped[bool] = mapped_column(Boolean, default=False)
    password_hash: Mapped[str | None] = mapped_column(VARCHAR(255), nullable=True)
    date_creation: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.now)

    @property
    def full_name(self) -> str:
        return f"{self.nom} {self.prenoms or ''}".strip()


class Campagne(Base):
    __tablename__ = "campagnes"
    id: Mapped[int] = mapped_column(primary_key=True)
    nom: Mapped[str] = mapped_column(VARCHAR(120))
    exercice: Mapped[int] = mapped_column(Integer)
    date_ouverture: Mapped[date | None] = mapped_column(Date, nullable=True)
    date_cloture: Mapped[date | None] = mapped_column(Date, nullable=True)
    statut: Mapped[str] = mapped_column(VARCHAR(20), default="Brouillon")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.now)


class Evaluation(Base):
    __tablename__ = "evaluations"
    id: Mapped[int] = mapped_column(primary_key=True)
    campagne_id: Mapped[int] = mapped_column(ForeignKey("campagnes.id"))
    salarie_id: Mapped[int] = mapped_column(ForeignKey("salaries.id"))
    numero: Mapped[str] = mapped_column(VARCHAR(20), unique=True)
    date_evaluation: Mapped[date | None] = mapped_column(Date, nullable=True)
    statut_n: Mapped[str] = mapped_column(VARCHAR(20), default="En cours")
    statut_n1: Mapped[str] = mapped_column(VARCHAR(20), default="En cours")
    statut_n2: Mapped[str] = mapped_column(VARCHAR(20), default="En cours")
    statut_global: Mapped[str] = mapped_column(VARCHAR(20), default="En cours")
    commentaire_global: Mapped[str | None] = mapped_column(Text, nullable=True)
    __table_args__ = (UniqueConstraint("campagne_id", "salarie_id"),)


class EvaluationLigne(Base):
    __tablename__ = "evaluation_lignes"
    id: Mapped[int] = mapped_column(primary_key=True)
    evaluation_id: Mapped[int] = mapped_column(ForeignKey("evaluations.id"))
    profil_id: Mapped[int] = mapped_column(ForeignKey("profils.id"))
    critere_id: Mapped[int] = mapped_column(ForeignKey("criteres.id"))
    etape: Mapped[str] = mapped_column(VARCHAR(5))  # 'N' | 'N+1' (enum SQL)
    critere_detail_id: Mapped[int | None] = mapped_column(
        ForeignKey("critere_details.id"), nullable=True
    )
    commentaire: Mapped[str | None] = mapped_column(Text, nullable=True)
    horodatage: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.now)
    __table_args__ = (
        UniqueConstraint("evaluation_id", "profil_id", "critere_id", "etape"),
        # commentaire obligatoire dès qu'un détail est coché
        CheckConstraint(
            "critere_detail_id IS NULL OR commentaire IS NULL "
            "OR length(trim(commentaire)) > 0",
            name="ck_ligne_commentaire_obligatoire",
        ),
    )


class Approbation(Base):
    __tablename__ = "approbations"
    id: Mapped[int] = mapped_column(primary_key=True)
    evaluation_id: Mapped[int] = mapped_column(
        ForeignKey("evaluations.id"), unique=True
    )
    decision: Mapped[str] = mapped_column(VARCHAR(40))  # Approuvé / Approuvé avec réserves
    observation: Mapped[str | None] = mapped_column(Text, nullable=True)
    auteur_id: Mapped[int] = mapped_column(ForeignKey("salaries.id"))
    horodatage: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.now)


class Notification(Base):
    __tablename__ = "notifications"
    id: Mapped[int] = mapped_column(primary_key=True)
    salarie_id: Mapped[int] = mapped_column(ForeignKey("salaries.id"))
    titre: Mapped[str] = mapped_column(VARCHAR(200))
    message: Mapped[str] = mapped_column(Text)
    lu: Mapped[bool] = mapped_column(Boolean, default=False)
    horodatage: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.now)


class AuditLog(Base):
    __tablename__ = "audit_log"
    id: Mapped[int] = mapped_column(primary_key=True)
    auteur_id: Mapped[int | None] = mapped_column(ForeignKey("salaries.id"), nullable=True)
    action: Mapped[str] = mapped_column(VARCHAR(60))
    table_cible: Mapped[str] = mapped_column(VARCHAR(60))
    enregistrement_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    avant: Mapped[dict | None] = mapped_column(JSON, nullable=True)   # jsonb
    apres: Mapped[dict | None] = mapped_column(JSON, nullable=True)   # jsonb
    justification: Mapped[str | None] = mapped_column(Text, nullable=True)
    horodatage: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.now)


class Param(Base):
    __tablename__ = "params"
    cle: Mapped[str] = mapped_column(VARCHAR(60), primary_key=True)
    valeur: Mapped[str] = mapped_column(VARCHAR(300))
    description: Mapped[str | None] = mapped_column(Text, nullable=True)