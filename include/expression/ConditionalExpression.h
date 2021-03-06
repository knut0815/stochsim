#pragma once
#include <memory>
#include "expression_common.h"
#include "NumberExpression.h"
namespace expression
{
	/// <summary>
	/// A conditional expression can represent two different sub-expression, depending on if the condition evaluates to true of false.
	/// Thus, it can be interpreted to represent:
	/// conditional_expression = condition ? expressionIfTrue : expressionIfFalse;
	/// </summary>
	class ConditionalExpression : public IExpression
	{
	public:
		ConditionalExpression(std::unique_ptr<IExpression> condition, std::unique_ptr<IExpression> expressionIfTrue, std::unique_ptr<IExpression> expressionIfFalse) :
			condition_(std::move(condition)),
			expressionIfTrue_(std::move(expressionIfTrue)),
			expressionIfFalse_(std::move(expressionIfFalse))
		{
		}
		virtual number Eval() const override
		{
			if (condition_->Eval() != 0)
				return expressionIfTrue_->Eval();
			else
				return expressionIfFalse_->Eval();
		}
		virtual std::unique_ptr<IExpression> Clone() const override
		{
			return std::make_unique<ConditionalExpression>(condition_->Clone(), expressionIfTrue_->Clone(), expressionIfFalse_->Clone());
		}
		virtual std::unique_ptr<IExpression> Simplify(const VariableRegister& variableRegister) const override
		{
			auto simpCondition = condition_->Simplify(variableRegister);
			if (dynamic_cast<NumberExpression*>(simpCondition.get()))
			{
				if (dynamic_cast<NumberExpression*>(simpCondition.get())->GetValue() != 0)
				{
					return expressionIfTrue_->Simplify(variableRegister);
				}
				else
				{
					return expressionIfFalse_->Simplify(variableRegister);
				}
			}
			else
			{
				return std::make_unique<ConditionalExpression>(std::move(simpCondition), expressionIfTrue_->Simplify(variableRegister), expressionIfFalse_->Simplify(variableRegister));
			}
		}
		virtual void PrintCmdl(std::ostream& stream, bool subExpression) const noexcept override
		{
			if (subExpression)
				stream << "(";
			condition_->PrintCmdl(stream, true);
			stream << " ? ";
			expressionIfTrue_->PrintCmdl(stream, true);
			stream << " : ";
			expressionIfFalse_->PrintCmdl(stream, true);
			if (subExpression)
				stream << ")";
		}
		virtual void Bind(const BindingRegister& bindingRegister) override
		{
			condition_->Bind(bindingRegister);
			expressionIfTrue_->Bind(bindingRegister);
			expressionIfFalse_->Bind(bindingRegister);
		}
	private:
		std::unique_ptr<IExpression> condition_;
		std::unique_ptr<IExpression> expressionIfTrue_;
		std::unique_ptr<IExpression> expressionIfFalse_;
	};
}