import { describe, it, expect, beforeEach } from "vitest"

class BillingConsumptionContract {
  constructor() {
    this.customerAccounts = new Map()
    this.waterMeters = new Map()
    this.consumptionRecords = new Map()
    this.billingInvoices = new Map()
    this.payments = new Map()
    this.authorizedReaders = new Map()
    this.nextRecordId = 1
    this.nextInvoiceId = 1
    this.nextPaymentId = 1
    this.totalRevenue = 0
    this.totalCustomers = 0
    this.contractOwner = "ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM"
    
    this.authorizedReaders.set(this.contractOwner, true)
  }
  
  createCustomerAccount(customer, accountId, name, address, sender) {
    if (sender !== this.contractOwner) {
      throw new Error("ERR-NOT-AUTHORIZED")
    }
    if (this.customerAccounts.has(customer)) {
      throw new Error("ERR-ACCOUNT-NOT-FOUND")
    }
    
    this.customerAccounts.set(customer, {
      accountId,
      name,
      address,
      accountBalance: 0,
      totalConsumption: 0,
      lastPayment: 0,
      paymentDueDate: 0,
      accountStatus: "active",
      createdAt: Date.now(),
    })
    
    this.totalCustomers++
    return { ok: customer }
  }
  
  installWaterMeter(meterId, customer, location, meterType, initialReading, sender) {
    if (sender !== this.contractOwner) {
      throw new Error("ERR-NOT-AUTHORIZED")
    }
    if (!this.customerAccounts.has(customer)) {
      throw new Error("ERR-ACCOUNT-NOT-FOUND")
    }
    
    this.waterMeters.set(meterId, {
      customer,
      location,
      meterType,
      currentReading: initialReading,
      lastReading: initialReading,
      lastReadingDate: Date.now(),
      installationDate: Date.now(),
      active: true,
    })
    
    return { ok: meterId }
  }
  
  recordMeterReading(meterId, newReading, billingPeriod, sender) {
    if (!this.authorizedReaders.get(sender)) {
      throw new Error("ERR-NOT-AUTHORIZED")
    }
    
    const meter = this.waterMeters.get(meterId)
    if (!meter || !meter.active) {
      throw new Error("ERR-METER-NOT-FOUND")
    }
    if (newReading < meter.currentReading) {
      throw new Error("ERR-INVALID-READING")
    }
    
    const consumption = newReading - meter.currentReading
    const recordId = this.nextRecordId++
    
    this.consumptionRecords.set(recordId, {
      customer: meter.customer,
      meterId,
      readingDate: Date.now(),
      currentReading: newReading,
      previousReading: meter.currentReading,
      consumptionAmount: consumption,
      billingPeriod,
      recordedBy: sender,
    })
    
    // Update meter
    meter.lastReading = meter.currentReading
    meter.currentReading = newReading
    meter.lastReadingDate = Date.now()
    
    // Update customer consumption
    const account = this.customerAccounts.get(meter.customer)
    account.totalConsumption += consumption
    
    return { ok: recordId }
  }
  
  generateInvoice(customer, billingPeriod, consumptionAmount, sender) {
    if (sender !== this.contractOwner) {
      throw new Error("ERR-NOT-AUTHORIZED")
    }
    if (!this.customerAccounts.has(customer)) {
      throw new Error("ERR-ACCOUNT-NOT-FOUND")
    }
    
    const invoiceId = this.nextInvoiceId++
    const tierBreakdown = this.calculateTieredPricing(consumptionAmount)
    const penalties = this.calculatePenalties(customer)
    const totalAmount = tierBreakdown.totalCost + penalties
    
    this.billingInvoices.set(invoiceId, {
      customer,
      billingPeriod,
      consumptionAmount,
      tier1Usage: tierBreakdown.tier1,
      tier2Usage: tierBreakdown.tier2,
      tier3Usage: tierBreakdown.tier3,
      tier4Usage: tierBreakdown.tier4,
      baseAmount: tierBreakdown.totalCost,
      penalties,
      totalAmount,
      dueDate: Date.now() + 30 * 24 * 60 * 60 * 1000, // 30 days
      paid: false,
      paidDate: 0,
      generatedAt: Date.now(),
    })
    
    // Update account balance
    const account = this.customerAccounts.get(customer)
    account.accountBalance += totalAmount
    
    return { ok: invoiceId }
  }
  
  calculateTieredPricing(consumption) {
    const TIER_1_LIMIT = 50000
    const TIER_2_LIMIT = 100000
    const TIER_3_LIMIT = 200000
    const TIER_1_PRICE = 100
    const TIER_2_PRICE = 150
    const TIER_3_PRICE = 200
    const TIER_4_PRICE = 300
    
    const tier1 = Math.min(consumption, TIER_1_LIMIT)
    const remaining1 = Math.max(0, consumption - TIER_1_LIMIT)
    const tier2 = Math.min(remaining1, TIER_2_LIMIT - TIER_1_LIMIT)
    const remaining2 = Math.max(0, remaining1 - (TIER_2_LIMIT - TIER_1_LIMIT))
    const tier3 = Math.min(remaining2, TIER_3_LIMIT - TIER_2_LIMIT)
    const tier4 = Math.max(0, remaining2 - (TIER_3_LIMIT - TIER_2_LIMIT))
    
    const totalCost = Math.floor(
        (tier1 * TIER_1_PRICE) / 1000 +
        (tier2 * TIER_2_PRICE) / 1000 +
        (tier3 * TIER_3_PRICE) / 1000 +
        (tier4 * TIER_4_PRICE) / 1000,
    )
    
    return { tier1, tier2, tier3, tier4, totalCost }
  }
  
  calculatePenalties(customer) {
    const account = this.customerAccounts.get(customer)
    if (account.paymentDueDate > 0 && Date.now() > account.paymentDueDate) {
      return Math.floor((account.accountBalance * 10) / 100) // 10% penalty
    }
    return 0
  }
  
  processPayment(invoiceId, amount, sender) {
    const invoice = this.billingInvoices.get(invoiceId)
    if (!invoice) {
      throw new Error("ERR-ACCOUNT-NOT-FOUND")
    }
    if (sender !== invoice.customer) {
      throw new Error("ERR-NOT-AUTHORIZED")
    }
    if (invoice.paid) {
      throw new Error("ERR-ALREADY-PAID")
    }
    if (amount < invoice.totalAmount) {
      throw new Error("ERR-INSUFFICIENT-BALANCE")
    }
    
    const paymentId = this.nextPaymentId++
    
    this.payments.set(paymentId, {
      customer: invoice.customer,
      invoiceId,
      amount,
      paymentMethod: "STX",
      paymentDate: Date.now(),
      transactionHash: "simulated-hash",
    })
    
    invoice.paid = true
    invoice.paidDate = Date.now()
    
    // Update account balance
    const account = this.customerAccounts.get(invoice.customer)
    account.accountBalance -= amount
    account.lastPayment = Date.now()
    
    this.totalRevenue += amount
    return { ok: paymentId }
  }
  
  getCustomerAccount(customer) {
    return this.customerAccounts.get(customer) || null
  }
  
  getWaterMeter(meterId) {
    return this.waterMeters.get(meterId) || null
  }
  
  getInvoice(invoiceId) {
    return this.billingInvoices.get(invoiceId) || null
  }
}

describe("Billing and Consumption Contract", () => {
  let contract
  const owner = "ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM"
  const customer = "ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG"
  const reader = "ST3NBRSFKX28FQ2ZJ1MAKX58HKHSDGNV5N7R21XCP"
  
  beforeEach(() => {
    contract = new BillingConsumptionContract()
  })
  
  describe("Account Management", () => {
    it("should create customer accounts", () => {
      const result = contract.createCustomerAccount(customer, "ACC001", "John Doe", "123 Main St", owner)
      expect(result.ok).toBe(customer)
      expect(contract.totalCustomers).toBe(1)
      
      const account = contract.getCustomerAccount(customer)
      expect(account.name).toBe("John Doe")
      expect(account.accountStatus).toBe("active")
    })
    
    it("should prevent duplicate accounts", () => {
      contract.createCustomerAccount(customer, "ACC001", "John Doe", "123 Main St", owner)
      
      expect(() => {
        contract.createCustomerAccount(customer, "ACC002", "Jane Doe", "456 Oak St", owner)
      }).toThrow("ERR-ACCOUNT-NOT-FOUND")
    })
  })
  
  describe("Meter Management", () => {
    beforeEach(() => {
      contract.createCustomerAccount(customer, "ACC001", "John Doe", "123 Main St", owner)
    })
    
    it("should install water meters", () => {
      const result = contract.installWaterMeter("METER001", customer, "123 Main St", "residential", 1000, owner)
      expect(result.ok).toBe("METER001")
      
      const meter = contract.getWaterMeter("METER001")
      expect(meter.customer).toBe(customer)
      expect(meter.currentReading).toBe(1000)
    })
    
    it("should require valid customer for meter installation", () => {
      const invalidCustomer = "ST3NBRSFKX28FQ2ZJ1MAKX58HKHSDGNV5N7R21XCP"
      
      expect(() => {
        contract.installWaterMeter("METER001", invalidCustomer, "123 Main St", "residential", 1000, owner)
      }).toThrow("ERR-ACCOUNT-NOT-FOUND")
    })
  })
  
  describe("Consumption Tracking", () => {
    beforeEach(() => {
      contract.createCustomerAccount(customer, "ACC001", "John Doe", "123 Main St", owner)
      contract.installWaterMeter("METER001", customer, "123 Main St", "residential", 1000, owner)
    })
    
    it("should record meter readings", () => {
      const result = contract.recordMeterReading("METER001", 1500, "2024-01", owner)
      expect(result.ok).toBe(1)
      
      const meter = contract.getWaterMeter("METER001")
      expect(meter.currentReading).toBe(1500)
      expect(meter.lastReading).toBe(1000)
      
      const account = contract.getCustomerAccount(customer)
      expect(account.totalConsumption).toBe(500)
    })
    
    it("should validate reading progression", () => {
      expect(() => {
        contract.recordMeterReading("METER001", 500, "2024-01", owner) // Lower than current
      }).toThrow("ERR-INVALID-READING")
    })
  })
  
  describe("Billing Calculations", () => {
    beforeEach(() => {
      contract.createCustomerAccount(customer, "ACC001", "John Doe", "123 Main St", owner)
    })
    
    it("should calculate tiered pricing correctly", () => {
      const pricing = contract.calculateTieredPricing(75000) // 75,000 liters
      
      expect(pricing.tier1).toBe(50000) // First 50k at tier 1
      expect(pricing.tier2).toBe(25000) // Next 25k at tier 2
      expect(pricing.tier3).toBe(0)
      expect(pricing.tier4).toBe(0)
      expect(pricing.totalCost).toBe(8750) // (50000*100 + 25000*150)/1000
    })
    
    it("should generate invoices with correct calculations", () => {
      const result = contract.generateInvoice(customer, "2024-01", 75000, owner)
      expect(result.ok).toBe(1)
      
      const invoice = contract.getInvoice(1)
      expect(invoice.consumptionAmount).toBe(75000)
      expect(invoice.baseAmount).toBe(8750)
      expect(invoice.totalAmount).toBe(8750) // No penalties for new account
    })
  })
  
  describe("Payment Processing", () => {
    beforeEach(() => {
      contract.createCustomerAccount(customer, "ACC001", "John Doe", "123 Main St", owner)
      contract.generateInvoice(customer, "2024-01", 75000, owner)
    })
    
    it("should process payments correctly", () => {
      const result = contract.processPayment(1, 8750, customer)
      expect(result.ok).toBe(1)
      expect(contract.totalRevenue).toBe(8750)
      
      const invoice = contract.getInvoice(1)
      expect(invoice.paid).toBe(true)
      
      const account = contract.getCustomerAccount(customer)
      expect(account.accountBalance).toBe(0)
    })
    
    it("should validate payment amounts", () => {
      expect(() => {
        contract.processPayment(1, 5000, customer) // Insufficient amount
      }).toThrow("ERR-INSUFFICIENT-BALANCE")
    })
    
    it("should prevent duplicate payments", () => {
      contract.processPayment(1, 8750, customer)
      
      expect(() => {
        contract.processPayment(1, 8750, customer)
      }).toThrow("ERR-ALREADY-PAID")
    })
  })
})
