# Exchange Rates ETL

## Overview

ETL pipeline that loads exchange rates from the PrivatBank API into Google BigQuery.

## Architecture

API → Python → Pandas → BigQuery

## Features

- Fetches USD and EUR exchange rates
- Cleans and transforms JSON response
- Prevents duplicate records
- Loads data into BigQuery
- Deployable as Google Cloud Functions Gen2

## Technologies

- Python
- Pandas
- Google BigQuery
- Google Cloud Functions
- REST API
