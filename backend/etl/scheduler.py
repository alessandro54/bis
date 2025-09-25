# backend/etl/scheduler.py
from apscheduler.schedulers.blocking import BlockingScheduler
from datetime import datetime
import logging
import os

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s - %(message)s",
)

sched = BlockingScheduler(timezone="UTC")


def heartbeat():
    logging.info("ETL heartbeat - scheduler alive at %s", datetime.utcnow().isoformat())


@sched.scheduled_job("interval", minutes=5, id="heartbeat")
def run_heartbeat():
    heartbeat()


# TODO: register your real jobs here, e.g.:
# from etl.jobs.aggregate_popularity import run_all_specs
# @sched.scheduled_job("cron", minute="*/15", id="aggregate_popularity")
# def aggregate():
#     run_all_specs()

if __name__ == "__main__":
    logging.info("Starting ETL scheduler…")
    sched.start()  # blocks forever
