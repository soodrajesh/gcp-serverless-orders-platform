import pytest

from app.orders import order_id_for, validate
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
