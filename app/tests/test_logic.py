import pytest

from app.orders import app as orders_app
from app.orders import order_id_for, valid_id, validate
from app.payments import decide

GOOD = {"sku": "ABC", "qty": 2, "amount": 50, "customer": "ana"}


def test_valid_order():
    assert validate(GOOD) is None


@pytest.mark.parametrize(
    "patch,frag",
    [
        ({"qty": 0}, "qty"),
        ({"qty": "2"}, "qty"),
        ({"qty": True}, "qty"),
        ({"amount": -1}, "amount"),
        ({"sku": ""}, "sku"),
        ({"customer": 5}, "customer"),
    ],
)
def test_invalid_orders(patch, frag):
    assert frag in validate({**GOOD, **patch})


def test_missing_field():
    b = dict(GOOD)
    del b["sku"]
    assert "missing" in validate(b)


def test_idempotency_key_maps_to_one_order_id():
    assert order_id_for("k1") == order_id_for("k1") != order_id_for("k2")


def test_payment_decisions():
    assert decide(5000, "ana", 1) == (402, "DECLINED")
    assert decide(10, "flaky-fred", 1) == (503, "UPSTREAM_UNAVAILABLE")
    assert decide(10, "flaky-fred", 2) == (200, "CHARGED")
    assert decide(10, "ana", 1) == (200, "CHARGED")


@pytest.mark.parametrize(
    "bad", ["x", "../internal/orders/x", "..%2Finternal", "a/b", "", "1234", "zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz"]
)
def test_junk_order_ids_are_rejected_before_firestore(bad):
    assert not valid_id(bad)


def test_generated_ids_are_valid():
    assert valid_id(order_id_for("any-key"))


def test_get_with_junk_id_is_404_without_touching_firestore(monkeypatch):
    def boom():
        raise AssertionError("Firestore must not be called for an invalid id")

    monkeypatch.setattr("app.orders.db", boom)
    assert orders_app.test_client().get("/orders/not-a-uuid").status_code == 404
    assert orders_app.test_client().patch("/internal/orders/not-a-uuid/status", json={"status": "FAILED"}).status_code == 404


def test_failed_publish_undoes_the_order_and_asks_the_client_to_retry(monkeypatch):
    deleted = []

    class Ref:
        def create(self, doc):
            return None

        def delete(self):
            deleted.append(True)

    class Db:
        def collection(self, _):
            return self

        def document(self, _):
            return Ref()

    class BadPublisher:
        def publish(self, *a, **k):
            raise RuntimeError("pubsub down")

    monkeypatch.setattr("app.orders.db", lambda: Db())
    monkeypatch.setattr("app.orders.publisher", lambda: BadPublisher())
    monkeypatch.setenv("TOPIC", "projects/x/topics/y")
    r = orders_app.test_client().post("/orders", json=GOOD, headers={"Idempotency-Key": "k"})
    assert r.status_code == 503 and deleted == [True]
