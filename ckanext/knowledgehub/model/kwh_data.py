import datetime

import ckan.logic as logic
from ckan import model
from ckan.model.meta import metadata, mapper, Session
from ckan.model.types import make_uuid
from ckan.model.domain_object import DomainObject

from sqlalchemy import types, ForeignKey, Column, Table, desc, asc, or_

__all__ = [
    'KWHData',
    'kwh_data_table',
    'setup'
]

kwh_data_table = None


class KWHData(DomainObject):

    @classmethod
    def get(cls, id_or_name=None, **kwargs):
        q = kwargs.pop('q', None)
        limit = kwargs.pop('limit', None)
        offset = kwargs.pop('offset', None)
        order_by = kwargs.pop('order_by', None)

        query = Session.query(cls).autoflush(False)
        query = query.filter_by(**kwargs)

        if id_or_name:
            query = query.filter(
                or_(cls.id == id_or_name, cls.title == id_or_name)
            )

        if q:
            query = query.filter(
                or_(cls.title.contains(q),
                    cls.title.ilike(r"%{}%".format(q)),
                    cls.description.contains(q),
                    cls.description.ilike(r"%{}%".format(q)))
            )

        if order_by:
            query = query.order_by(order_by)

        if limit:
            query = query.limit(limit)

        if offset:
            query = query.offset(offset)

        return query

    @classmethod
    def update(cls, filter, data):
        obj = Session.query(cls).filter_by(**filter)
        obj.update(data)
        Session.commit()

        return obj.first()

    @classmethod
    def delete(cls, filter):
        obj = Session.query(cls).filter_by(**filter).first()
        if obj:
            Session.delete(obj)
            Session.commit()
        else:
            raise logic.NotFound('data not found')


kwh_data_table = Table(
    'kwh_data',
    metadata,
    Column(
        'id',
        types.UnicodeText,
        primary_key=True,
        default=make_uuid),
    Column(
        'type',
        types.UnicodeText,
        nullable=False),
    Column(
        'title',
        types.UnicodeText,
        nullable=False),
    Column(
        'description',
        types.UnicodeText),
    Column(
        'user',
        types.UnicodeText,
        ForeignKey('user.id', ondelete='CASCADE')),
    Column(
        'theme',
        types.UnicodeText,
        ForeignKey('theme.id', ondelete='CASCADE')),
    Column(
        'sub_theme',
        types.UnicodeText,
        ForeignKey('sub_themes.id', ondelete='CASCADE')),
    Column(
        'research_question',
        types.UnicodeText,
        ForeignKey('research_question.id', ondelete='CASCADE')),
    Column(
        'dataset',
        types.UnicodeText,
        ForeignKey('package.id', ondelete='CASCADE')),
    Column(
        'visualization',
        types.UnicodeText,
        ForeignKey('resource_view.id', ondelete='CASCADE')),
    Column(
        'dashboard',
        types.UnicodeText,
        ForeignKey('ckanext_knowledgehub_dashboard.id', ondelete='CASCADE')),
    Column(
        'created_at',
        types.DateTime,
        default=datetime.datetime.utcnow,
        onupdate=datetime.datetime.utcnow)
)


mapper(
    KWHData,
    kwh_data_table,
)


def setup():
    metadata.create_all(model.meta.engine)
