<?php

/**
 * Invoice Ninja (https://invoiceninja.com).
 *
 * @link https://github.com/invoiceninja/invoiceninja source repository
 *
 * @copyright Copyright (c) 2026. Invoice Ninja LLC (https://invoiceninja.com)
 *
 * @license https://www.elastic.co/licensing/elastic-license
 */

namespace App\Services\License;

use App\Models\Account;
use Carbon\Carbon;

/**
 * Evaluates the license stored on this instance.
 *
 * The license state is read from the account itself — no external service is
 * contacted — so a license remains valid for as long as its recorded expiry
 * allows.
 */
class LicenseValidityService
{
    /**
     * An expiry beyond this window is treated as invalid.
     */
    private const MAX_LICENSE_DAYS = 395;

    /**
     * Is the license recorded on the account still valid?
     */
    public function isValid(Account $account): bool
    {
        if ($account->plan !== Account::PLAN_WHITE_LABEL) {
            return false;
        }

        if (! $account->plan_expires) {
            return false;
        }

        $expires = Carbon::parse($account->plan_expires);

        if ($expires->lt(now())) {
            return false;
        }

        if ($expires->gt(now()->addDays(self::MAX_LICENSE_DAYS))) {
            return false;
        }

        return true;
    }
}
