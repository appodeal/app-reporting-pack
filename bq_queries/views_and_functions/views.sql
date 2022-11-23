# Copyright 2022 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

-- Represents basic app campaign settings that are used when creating
-- final tables for dashboards
CREATE OR REPLACE VIEW `{bq_dataset}.AppCampaignSettingsView`
AS (
    SELECT
        campaign_id,
        campaign_sub_type,
        app_id,
        app_store,
        CASE
            WHEN bidding_strategy = "OPTIMIZE_INSTALLS_TARGET_INSTALL_COST" THEN "Installs"
            WHEN bidding_strategy = "OPTIMIZE_IN_APP_CONVERSIONS_TARGET_INSTALL_COST" THEN "Installs Advanced"
            WHEN bidding_strategy = "OPTIMIZE_IN_APP_CONVERSIONS_TARGET_CONVERSION_COST" THEN "Actions"
            WHEN bidding_strategy = "OPTIMIZE_INSTALLS_WITHOUT_TARGET_INSTALL_COST" THEN "Maximize Conversions"
            WHEN bidding_strategy = "OPTIMIZE_RETURN_ON_ADVERTISING_SPEND" THEN "Target ROAS"
            WHEN bidding_strategy = "OPTIMIZE_PRE_REGISTRATION_CONVERSION_VOLUME" THEN "Preregistrations"
            ELSE "Unknown"
            END AS bidding_strategy,
        start_date,
        IF(conversion_type = "DOWNLOAD", conversion_id, NULL) AS install_conversion_id,
        IF(conversion_type != "DOWNLOAD", conversion_id, NULL) AS inapp_conversion_id,
        ARRAY_TO_STRING(ARRAY_AGG(DISTINCT conversion_source ORDER BY conversion_source), "|") AS conversion_sources,
        ARRAY_TO_STRING(ARRAY_AGG(DISTINCT conversion_name ORDER BY conversion_name), " | ") AS target_conversions,
        COUNT(conversion_name) AS n_of_target_conversions
    FROM {bq_dataset}.app_campaign_settings
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
);

-- Campaign level geo and language targeting
CREATE OR REPLACE VIEW `{bq_dataset}.GeoLanguageView` AS (
    SELECT
        COALESCE(CampaignGeoTarget.campaign_id, CampaignLanguages.campaign_id) AS campaign_id,
        ARRAY_TO_STRING(ARRAY_AGG(DISTINCT country_code ORDER BY country_code), " | ") AS geos,
        ARRAY_TO_STRING(ARRAY_AGG(DISTINCT language ORDER BY language), " | ") AS languages
    FROM {bq_dataset}.campaign_geo_targets AS CampaignGeoTarget
    LEFT JOIN {bq_dataset}.geo_target_constant AS GeoTargetConstant
        ON CampaignGeoTarget.geo_target = CAST(GeoTargetConstant.constant_id AS STRING)
    FULL JOIN {bq_dataset}.campaign_languages AS CampaignLanguages
        ON CampaignGeoTarget.campaign_id = CampaignLanguages.campaign_id
    GROUP BY 1
);


-- Conversion Lag adjustment placeholder data
-- TODO: Once conversion lag adjustment algorithm is ready switch to it.
CREATE OR REPLACE VIEW `{bq_dataset}.ConversionLagAdjustments` AS (
    SELECT
        DATE_SUB(CURRENT_DATE(), INTERVAL lag_day DAY) AS adjustment_date,
        network,
        conversion_id,
        lag_adjustment
    FROM {bq_dataset}.conversion_lag_adjustments
);

CREATE OR REPLACE VIEW `{bq_dataset}.AssetCohorts` AS (
    SELECT
        day_of_interaction,
        ad_group_id,
        asset_id,
        field_type,
        network,
        STRUCT(
            ARRAY_AGG(lag ORDER BY lag) AS lags,
            ARRAY_AGG(installs ORDER BY lag) AS installs,
            ARRAY_AGG(inapps ORDER BY lag) AS inapps,
            ARRAY_AGG(conversions_value ORDER BY lag) AS conversions_value,
            ARRAY_AGG(view_through_conversions ORDER BY lag) AS view_through_conversions
        ) AS lag_data
    FROM `{bq_dataset}.conversion_lags_*`
    WHERE
        day_of_interaction IS NOT NULL
        AND lag <= 90
    GROUP BY 1, 2, 3, 4, 5
);
