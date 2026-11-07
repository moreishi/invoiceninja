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

namespace Tests\Unit;

use App\Models\Account;
use App\Services\License\LicenseValidityService;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Tests\MockAccountData;
use Tests\TestCase;

class LicenseValidityTest extends TestCase
{
    use DatabaseTransactions;
    use MockAccountData;

    private LicenseValidityService $service;

    protected function setUp(): void
    {
        parent::setUp();
        $this->makeTestData();
        $this->service = new LicenseValidityService();
    }

    public function testUnexpiredLicenseIsValid(): void
    {
        $account = $this->account;
        $account->plan = Account::PLAN_WHITE_LABEL;
        $account->plan_expires = now()->addMonth()->format('Y-m-d');
        $account->save();

        $this->assertTrue($this->service->isValid($account));
    }

    public function testExpiredLicenseIsNotValid(): void
    {
        $account = $this->account;
        $account->plan = Account::PLAN_WHITE_LABEL;
        $account->plan_expires = now()->subDay()->format('Y-m-d');
        $account->save();

        $this->assertFalse($this->service->isValid($account));
    }

    public function testLicenseWithoutExpiryIsNotValid(): void
    {
        $account = $this->account;
        $account->plan = Account::PLAN_WHITE_LABEL;
        $account->plan_expires = null;
        $account->save();

        $this->assertFalse($this->service->isValid($account));
    }

    public function testLicenseWithoutPlanIsNotValid(): void
    {
        $account = $this->account;
        $account->plan = null;
        $account->plan_expires = now()->addMonth()->format('Y-m-d');
        $account->save();

        $this->assertFalse($this->service->isValid($account));
    }

    public function testImplausibleExpiryIsNotValid(): void
    {
        $account = $this->account;
        $account->plan = Account::PLAN_WHITE_LABEL;
        $account->plan_expires = now()->addYears(5)->format('Y-m-d');
        $account->save();

        $this->assertFalse($this->service->isValid($account));
    }
}
